#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
HELPER="${SCRIPT_DIR}/xivl_otp_helper.py"
DEFAULT_CONFIG="${HOME}/.config/xivl-otp-helper/config.json"
STATE_DIR="${XDG_STATE_HOME:-${HOME}/.local/state}/xivl-otp-helper"
LOG_FILE="${STATE_DIR}/helper.log"
HELPER_PID=""
STEAM_URI="steam://rungameid/39210"

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required but was not found in PATH." >&2
  exit 1
fi

if ! command -v steam >/dev/null 2>&1; then
  echo "Steam is required but was not found in PATH." >&2
  echo "Install Steam and make sure the steam command is available." >&2
  exit 1
fi

if [[ -z "${XIVL_OTP_SECRET:-}" && ! -f "${DEFAULT_CONFIG}" ]]; then
  echo "No OTP helper configuration found." >&2
  echo "Run ./setup.sh first, or set XIVL_OTP_SECRET in your shell." >&2
  exit 1
fi

mkdir -p "${STATE_DIR}"
: > "${LOG_FILE}"

cleanup_helper() {
  if [[ -n "${HELPER_PID}" ]] && kill -0 "${HELPER_PID}" 2>/dev/null; then
    kill "${HELPER_PID}" 2>/dev/null || true
    wait "${HELPER_PID}" 2>/dev/null || true
  fi
  HELPER_PID=""
}

cleanup_on_exit() {
  cleanup_helper
}

trap cleanup_on_exit EXIT INT TERM

echo "Starting OTP helper in background..."
python3 -u "${HELPER}" --autofill-once --verbose >"${LOG_FILE}" 2>&1 &
HELPER_PID=$!

echo "Launching FFXIV through Steam..."
steam "${STEAM_URI}"

if wait "${HELPER_PID}"; then
  exit 0
fi

exit $?
