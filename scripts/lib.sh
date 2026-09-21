# Shared helpers for macOS and Linux hosts (including Windows WSL2).
# shellcheck shell=bash

require_unix() {
  case "$(uname -s)" in
    Darwin | Linux) ;;
    *)
      echo "unsupported OS: $(uname -s)" >&2
      echo "Run on macOS, Linux, or Windows WSL2." >&2
      exit 1
      ;;
  esac
}

# Decode stdin. GNU coreutils, BusyBox, and BSD/macOS each use a different flag.
b64decode() {
  local encoded
  encoded="$(cat)"
  if printf '%s' "$encoded" | base64 --decode 2>/dev/null; then
    return 0
  fi
  if printf '%s' "$encoded" | base64 -d 2>/dev/null; then
    return 0
  fi
  printf '%s' "$encoded" | base64 -D
}

# IANA name such as Europe/Berlin or America/Los_Angeles.
host_timezone() {
  local tz="" target=""

  if [[ -n "${TZ:-}" && "${TZ}" == */* && "${TZ}" != :* ]]; then
    printf '%s\n' "${TZ}"
    return 0
  fi

  if [[ -f /etc/timezone ]]; then
    tz="$(tr -d '[:space:]' </etc/timezone || true)"
    if [[ -n "$tz" && "$tz" == */* ]]; then
      printf '%s\n' "$tz"
      return 0
    fi
  fi

  if command -v timedatectl >/dev/null 2>&1; then
    tz="$(timedatectl show -p Timezone --value 2>/dev/null || true)"
    if [[ -n "$tz" && "$tz" != "n/a" ]]; then
      printf '%s\n' "$tz"
      return 0
    fi
  fi

  if [[ -L /etc/localtime ]]; then
    target="$(readlink /etc/localtime 2>/dev/null || true)"
    tz="${target##*zoneinfo/}"
    if [[ "$tz" == "$target" ]]; then
      tz="${target##*timezone/}"
    fi
    if [[ -n "$tz" && "$tz" == */* ]]; then
      printf '%s\n' "$tz"
      return 0
    fi
  fi

  printf 'UTC\n'
}
