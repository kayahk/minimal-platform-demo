#!/usr/bin/env python3
"""Tiny UI that proves Vault and CNPG credentials are in use in this pod."""

from __future__ import annotations

import html
import json
import os
import subprocess
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ENVIRONMENT = os.environ.get("ENVIRONMENT", "")
PROJECT = os.environ.get("PROJECT", "")
SERVICE = os.environ.get("SERVICE", "")
PORT = int(os.environ.get("PORT", "80"))
PREFIXES = [item for item in os.environ.get("VAULT_PREFIXES", "secrets,configurations").split(",") if item]
DATABASE_ENABLED = os.environ.get("DATABASE_ENABLED", "").lower() in {"1", "true", "yes"}


def secret_dir(prefix: str) -> Path:
    return Path("/vault") / prefix


def kv_path(prefix: str) -> str:
    return f"{prefix}/{ENVIRONMENT}/{PROJECT}-{SERVICE}/demo"


def read_mount(prefix: str) -> dict[str, str]:
    directory = secret_dir(prefix)
    if not directory.is_dir():
        return {}
    data: dict[str, str] = {}
    for entry in sorted(directory.iterdir()):
        if not entry.is_file() or entry.name.startswith(".") or entry.name.startswith("_"):
            continue
        data[entry.name] = entry.read_text(encoding="utf-8", errors="replace")
    return data


def probe_postgres() -> dict:
    info = {
        "host": os.environ.get("PGHOST", ""),
        "port": os.environ.get("PGPORT", "5432"),
        "dbname": os.environ.get("PGDATABASE", ""),
        "user": os.environ.get("PGUSER", ""),
        "passwordMounted": bool(os.environ.get("PGPASSWORD")),
    }
    if not DATABASE_ENABLED:
        return {"enabled": False, "ok": False, **info}
    if not info["host"] or not info["dbname"] or not info["user"] or not info["passwordMounted"]:
        return {
            "enabled": True,
            "ok": False,
            "error": "database credentials are not mounted",
            **info,
        }
    try:
        completed = subprocess.run(
            [
                "psql",
                "-At",
                "-c",
                "select current_user || '|' || current_database() || '|' "
                "|| coalesce(inet_server_addr()::text, 'unknown') || '|' "
                "|| current_timestamp::text",
            ],
            capture_output=True,
            text=True,
            timeout=5,
            env=os.environ.copy(),
            check=False,
        )
    except FileNotFoundError:
        return {"enabled": True, "ok": False, "error": "psql is not installed", **info}
    except Exception as exc:  # noqa: BLE001
        return {"enabled": True, "ok": False, "error": str(exc), **info}
    if completed.returncode != 0:
        err = (completed.stderr or completed.stdout or "psql failed").strip()
        return {"enabled": True, "ok": False, "error": err, **info}
    parts = (completed.stdout.strip().split("|") + ["", "", "", ""])[:4]
    user, dbname, addr, now = parts
    return {
        "enabled": True,
        "ok": True,
        **info,
        "currentUser": user,
        "currentDatabase": dbname,
        "serverAddr": addr,
        "serverTime": now,
    }


def payload() -> dict:
    mounts = {prefix: read_mount(prefix) for prefix in PREFIXES}
    database = probe_postgres()
    return {
        "project": PROJECT,
        "service": SERVICE,
        "environment": ENVIRONMENT,
        "synced": any(mounts.values()),
        "database": database,
        "mounts": {
            prefix: {
                "vaultPath": kv_path(prefix),
                "mountPath": str(secret_dir(prefix)),
                "data": data,
            }
            for prefix, data in mounts.items()
        },
    }


def render_page(body: dict) -> str:
    rows = []
    for prefix, mount in body["mounts"].items():
        if mount["data"]:
            for key, value in mount["data"].items():
                rows.append(
                    "<tr>"
                    f"<td><code>{html.escape(prefix)}</code></td>"
                    f"<td><code>{html.escape(key)}</code></td>"
                    f"<td><code>{html.escape(value)}</code></td>"
                    "</tr>"
                )
        else:
            rows.append(
                "<tr class='empty'>"
                f"<td><code>{html.escape(prefix)}</code></td>"
                "<td colspan='2'>waiting for Vault Secrets Operator to sync this mount</td>"
                "</tr>"
            )

    status = "Secrets synced from Vault" if body["synced"] else "Waiting for Vault Secrets Operator"
    status_class = "ok" if body["synced"] else "wait"
    paths = "".join(
        f"<li><code>{html.escape(mount['vaultPath'])}</code></li>"
        for mount in body["mounts"].values()
    )
    table_rows = "".join(rows) or (
        "<tr class='empty'><td colspan='3'>No Vault mounts configured.</td></tr>"
    )

    database = body["database"]
    if not database.get("enabled"):
        db_status = "No database claimed for this service"
        db_class = "wait"
        db_body = "<p class='sub'>This workload has no <code>spec.database</code>.</p>"
    elif database.get("ok"):
        db_status = f"Connected to {database.get('currentDatabase', '')} as {database.get('currentUser', '')}"
        db_class = "ok"
        db_body = f"""
    <table>
      <thead><tr><th>field</th><th>value</th></tr></thead>
      <tbody>
        <tr><td>host</td><td><code>{html.escape(database.get("host", ""))}</code></td></tr>
        <tr><td>database</td><td><code>{html.escape(database.get("currentDatabase", ""))}</code></td></tr>
        <tr><td>user</td><td><code>{html.escape(database.get("currentUser", ""))}</code></td></tr>
        <tr><td>server</td><td><code>{html.escape(database.get("serverAddr", ""))}</code></td></tr>
        <tr><td>now</td><td><code>{html.escape(database.get("serverTime", ""))}</code></td></tr>
      </tbody>
    </table>
    <p>Password came from CNPG secret <code>postgres-app</code> (copied from
      <code>cnpg-system/platform-postgres-app</code>). It is not printed here.</p>
"""
    else:
        db_status = "Database credentials are mounted, but the connection failed"
        db_class = "wait"
        db_body = f"<p class='empty'><code>{html.escape(database.get('error', 'unknown error'))}</code></p>"

    return f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>{html.escape(SERVICE or "push-service")} platform demo</title>
  <style>
    :root {{ color-scheme: dark; }}
    body {{
      margin: 0;
      font-family: ui-sans-serif, system-ui, sans-serif;
      background: #0f172a;
      color: #e2e8f0;
    }}
    main {{ max-width: 840px; margin: 0 auto; padding: 2.5rem 1.25rem; }}
    h1 {{ margin: 0 0 0.4rem; font-size: 1.7rem; }}
    h2 {{ margin: 2rem 0 0.75rem; font-size: 1.15rem; }}
    .sub {{ color: #94a3b8; margin-bottom: 1.5rem; }}
    .status {{
      display: inline-block;
      padding: 0.35rem 0.7rem;
      border-radius: 999px;
      font-size: 0.9rem;
      margin-bottom: 1.25rem;
    }}
    .ok {{ background: #14532d; color: #bbf7d0; }}
    .wait {{ background: #7c2d12; color: #fed7aa; }}
    table {{
      width: 100%;
      border-collapse: collapse;
      background: #1e293b;
      border-radius: 12px;
      overflow: hidden;
    }}
    th, td {{ text-align: left; padding: 0.75rem 0.9rem; border-bottom: 1px solid #334155; }}
    th {{ color: #93c5fd; font-weight: 600; }}
    tr.empty td, p.empty {{ color: #fbbf24; }}
    code {{ font-family: ui-monospace, SFMono-Regular, monospace; font-size: 0.92rem; }}
    ul {{ color: #cbd5e1; }}
    a {{ color: #93c5fd; }}
  </style>
</head>
<body>
  <main>
    <h1>{html.escape(PROJECT or "project")}/{html.escape(SERVICE or "service")}</h1>
    <p class="sub">environment <strong>{html.escape(ENVIRONMENT or "unknown")}</strong>
      · values below were never in Git. Vault Secrets Operator and CloudNativePG
      copied them into this pod.</p>
    <h2>Vault</h2>
    <div class="status {status_class}">{html.escape(status)}</div>
    <table>
      <thead><tr><th>mount</th><th>key</th><th>value</th></tr></thead>
      <tbody>{table_rows}</tbody>
    </table>
    <p>Vault paths:</p>
    <ul>{paths}</ul>
    <h2>PostgreSQL</h2>
    <div class="status {db_class}">{html.escape(db_status)}</div>
    {db_body}
    <p>Machine-readable copy:
      <a href="/api/secrets"><code>/api/secrets</code></a>
      · <a href="/api/database"><code>/api/database</code></a></p>
  </main>
</body>
</html>
"""


class Handler(BaseHTTPRequestHandler):
    def log_message(self, format: str, *args) -> None:  # noqa: A003
        return

    def _send(self, status: int, content_type: str, body: bytes) -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:  # noqa: N802
        if self.path == "/healthz":
            self._send(200, "text/plain; charset=utf-8", b"ok\n")
            return
        if self.path == "/readyz":
            database = probe_postgres()
            if DATABASE_ENABLED and not database.get("ok"):
                self._send(503, "application/json", json.dumps(database).encode("utf-8") + b"\n")
                return
            self._send(200, "text/plain; charset=utf-8", b"ok\n")
            return
        body = payload()
        if self.path == "/api/database":
            self._send(200, "application/json", json.dumps(body["database"], indent=2).encode("utf-8") + b"\n")
            return
        if self.path == "/api/secrets":
            self._send(200, "application/json", json.dumps(body, indent=2).encode("utf-8") + b"\n")
            return
        if self.path in ("/", "/index.html"):
            self._send(200, "text/html; charset=utf-8", render_page(body).encode("utf-8"))
            return
        self._send(404, "text/plain; charset=utf-8", b"not found\n")


if __name__ == "__main__":
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
