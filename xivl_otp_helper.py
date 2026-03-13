#!/usr/bin/env python3
"""Minimal local helper for XIVLauncher OTP autofill."""

from __future__ import annotations

import base64
import hashlib
import hmac
import json
import os
import struct
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Any


DEFAULT_CONFIG_PATH = Path("~/.config/xivl-otp-helper/config.json").expanduser()
LISTENER_BASE_URL = "http://127.0.0.1:4646"
LISTENER_TIMEOUT = 2.0
LISTENER_INTERVAL = 2.0
DEFAULT_WATCH_TIMEOUT = 180.0
LISTENER_BANNER_APP = "XIVLauncher"
LISTENER_BANNER_VERSION_PREFIX = "core-"


class HelperError(Exception):
    """Raised for expected helper failures."""


@dataclass
class ListenerState:
    up: bool
    banner: dict[str, Any] | None = None
    raw_body: str = ""


def log(message: str) -> None:
    timestamp = time.strftime("%Y-%m-%d %H:%M:%S")
    print(f"[{timestamp}] {message}")


def load_config(path: Path) -> dict[str, Any]:
    try:
        raw = path.read_text(encoding="utf-8")
    except FileNotFoundError:
        return {}
    except OSError as exc:
        raise HelperError(f"Failed to read config file {path}: {exc}") from exc

    try:
        data = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise HelperError(f"Config file is not valid JSON: {path}: {exc}") from exc

    if not isinstance(data, dict):
        raise HelperError(f"Config file must contain a JSON object: {path}")

    return data


def normalize_base32_secret(secret: str) -> str:
    normalized = "".join(secret.split()).upper()
    if not normalized:
        raise HelperError("OTP secret is empty")

    padding = (-len(normalized)) % 8
    return normalized + ("=" * padding)


def load_secret(config_path: Path) -> bytes:
    env_secret = os.environ.get("XIVL_OTP_SECRET")
    if env_secret:
        source_secret = env_secret
    else:
        config = load_config(config_path)
        source_secret = config.get("secret", "")

    if not source_secret:
        raise HelperError(
            "No OTP secret found. Set XIVL_OTP_SECRET or add a secret to "
            f"{config_path}."
        )

    try:
        return base64.b32decode(normalize_base32_secret(source_secret), casefold=True)
    except Exception as exc:  # pragma: no cover - stdlib decoder error types vary
        raise HelperError("OTP secret is not valid Base32") from exc


def generate_totp(secret: bytes, for_time: int | None = None, *, step: int = 30) -> str:
    if for_time is None:
        for_time = int(time.time())

    counter = for_time // step
    message = struct.pack(">Q", counter)
    digest = hmac.new(secret, message, hashlib.sha1).digest()
    offset = digest[-1] & 0x0F
    code_int = struct.unpack(">I", digest[offset : offset + 4])[0] & 0x7FFFFFFF
    code = f"{code_int % 1_000_000:06d}"

    if len(code) != 6 or not code.isdigit():
        raise HelperError("Generated OTP is invalid")

    return code


def http_get(url: str) -> tuple[int, str]:
    request = urllib.request.Request(url, method="GET")
    try:
        with urllib.request.urlopen(request, timeout=LISTENER_TIMEOUT) as response:
            status = response.getcode()
            body = response.read().decode("utf-8", errors="replace")
            return status, body
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        return exc.code, body
    except urllib.error.URLError as exc:
        raise HelperError(f"HTTP request failed: {exc}") from exc


def detect_listener() -> ListenerState:
    try:
        status, body = http_get(f"{LISTENER_BASE_URL}/")
    except HelperError:
        return ListenerState(up=False)

    if status != 200:
        return ListenerState(up=False, raw_body=body)

    try:
        banner = json.loads(body)
    except json.JSONDecodeError:
        banner = None

    if isinstance(banner, dict):
        if (
            banner.get("app") == LISTENER_BANNER_APP
            and str(banner.get("version", "")).startswith(LISTENER_BANNER_VERSION_PREFIX)
        ):
            return ListenerState(up=True, banner=banner, raw_body=body)

    if LISTENER_BANNER_APP in body and LISTENER_BANNER_VERSION_PREFIX in body:
        return ListenerState(up=True, raw_body=body)

    return ListenerState(up=False, banner=banner if isinstance(banner, dict) else None, raw_body=body)


def submit_code(code: str) -> bool:
    if len(code) != 6 or not code.isdigit():
        raise HelperError("Refusing to submit an invalid OTP code")

    encoded_code = urllib.parse.quote(code, safe="")
    status, body = http_get(f"{LISTENER_BASE_URL}/ffxivlauncher/{encoded_code}")
    if status != 200:
        raise HelperError(f"Submission failed with HTTP {status}")

    return LISTENER_BANNER_APP in body


def run_watch_until(
    secret: bytes,
    *,
    interval: float,
    exit_after_submit: bool = False,
    timeout: float | None = None,
) -> int:
    session_seen = False
    last_submitted_code: str | None = None
    deadline = None if timeout is None else (time.monotonic() + timeout)

    log(f"Watching XIVLauncher listener at {LISTENER_BASE_URL}/ every {interval:.1f}s.")

    try:
        while True:
            if deadline is not None and time.monotonic() >= deadline:
                log(
                    "Timed out waiting for the XIVLauncher OTP listener.",
                )
                return 1

            state = detect_listener()

            if not state.up:
                if session_seen:
                    log("Listener disappeared; resetting session state.")
                session_seen = False
                last_submitted_code = None
                time.sleep(interval)
                continue

            if not session_seen:
                session_seen = True
                last_submitted_code = None
                log("Listener detected.")

            code = generate_totp(secret)
            if code != last_submitted_code:
                if submit_code(code):
                    last_submitted_code = code
                    log("Submitted current OTP to XIVLauncher listener.")
                    if exit_after_submit:
                        return 0
                else:
                    log("Submission returned an unexpected response.")

            time.sleep(interval)
    except KeyboardInterrupt:
        log("Stopped by user.")
        return 130


def main() -> int:
    try:
        if len(sys.argv) > 1:
            print("Usage: python3 xivl_otp_helper.py", file=sys.stderr)
            return 2
        secret = load_secret(DEFAULT_CONFIG_PATH)
        return run_watch_until(
            secret,
            interval=LISTENER_INTERVAL,
            exit_after_submit=True,
            timeout=DEFAULT_WATCH_TIMEOUT,
        )
    except HelperError as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
