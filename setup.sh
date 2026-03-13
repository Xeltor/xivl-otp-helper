#!/usr/bin/env bash
set -euo pipefail

CONFIG_DIR="${HOME}/.config/xivl-otp-helper"
CONFIG_FILE="${CONFIG_DIR}/config.json"

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required but was not found in PATH." >&2
  exit 1
fi

if [[ ! -f "${CONFIG_FILE}" ]]; then
  mkdir -p "${CONFIG_DIR}"
else
  echo "A config file already exists at ${CONFIG_FILE}."
  read -r -p "Do you want to replace it? [y/N] " replace_answer
  case "${replace_answer}" in
    y|Y|yes|YES)
      ;;
    *)
      echo "Leaving the existing config in place."
      exit 0
      ;;
  esac
fi

echo "Paste your Base32 TOTP secret for XIVLauncher."
echo "The input will be hidden."

read -r -s -p "Secret: " secret_first
echo
read -r -s -p "Confirm secret: " secret_second
echo

if [[ "${secret_first}" != "${secret_second}" ]]; then
  echo "The two entries did not match. Setup aborted." >&2
  exit 1
fi

python3 - "${CONFIG_FILE}" "${secret_first}" <<'PY'
import base64
import json
import os
import sys

config_path = os.path.expanduser(sys.argv[1])
secret = sys.argv[2]

normalized = "".join(secret.split()).upper()
if not normalized:
    print("The secret was empty. Setup aborted.", file=sys.stderr)
    raise SystemExit(1)

padding = "=" * (-len(normalized) % 8)

try:
    decoded = base64.b32decode(normalized + padding, casefold=True)
except Exception:
    print("That does not look like a valid Base32 TOTP secret. Setup aborted.", file=sys.stderr)
    raise SystemExit(1)

if not decoded:
    print("The decoded secret was empty. Setup aborted.", file=sys.stderr)
    raise SystemExit(1)

os.makedirs(os.path.dirname(config_path), exist_ok=True)
with open(config_path, "w", encoding="utf-8") as handle:
    json.dump({"secret": normalized}, handle, indent=2)
    handle.write("\n")
os.chmod(config_path, 0o600)
PY

echo "Saved OTP helper config to ${CONFIG_FILE}."
echo "Run ./start-ffxiv.sh to launch XIVLauncher with OTP autofill."
