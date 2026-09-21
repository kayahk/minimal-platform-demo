#!/usr/bin/env python3
"""Check registry files against the local JSON Schema."""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCHEMA_PATH = ROOT / "registry/schema/config.schema.json"
REGISTRY = ROOT / "registry"


def main() -> int:
    schema = json.loads(SCHEMA_PATH.read_text())
    files = list(REGISTRY.glob("**/config.json"))
    if not files:
        print("no config.json files found", file=sys.stderr)
        return 1

    try:
        import jsonschema
    except ImportError:
        jsonschema = None
        print("jsonschema is not installed; checking required keys only")

    errors = 0
    for path in files:
        data = json.loads(path.read_text())
        rel = path.relative_to(ROOT)
        if jsonschema:
            validator = jsonschema.Draft202012Validator(schema)
            issues = sorted(validator.iter_errors(data), key=lambda e: e.path)
            if issues:
                errors += 1
                print(f"{rel}:")
                for issue in issues:
                    location = ".".join(str(p) for p in issue.path) or "(root)"
                    print(f"  {location}: {issue.message}")
            else:
                print(f"{rel}: ok")
        else:
            missing = [k for k in ("projectName", "serviceName", "spec") if k not in data]
            if missing:
                errors += 1
                print(f"{rel}: missing {missing}")
            else:
                print(f"{rel}: ok (required keys)")
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
