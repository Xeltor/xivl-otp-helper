# xivl-otp-helper

`xivl-otp-helper` is a small local helper that generates your FFXIV one-time password and autofills it into XIVLauncher on Linux. It is Linux-only, Steam-only, and uses XIVLauncher's built-in `Use XIVLauncher authenticator/OTP macros` listener to submit the current 6-digit OTP locally.

## Quick Start

Project path assumed below:

```bash
cd ~/Projects/xivl-otp-helper
```

Before you start:

- You are on Linux.
- You launch FFXIV through Steam.
- `python3` is installed.
- XIVLauncher is installed and working normally on your system.
- You have your Base32 TOTP secret ready.

Setup and first launch:

1. Run `./setup.sh`
2. Enter your Base32 TOTP secret when prompted
3. In XIVLauncher, enable `Use XIVLauncher authenticator/OTP macros`
4. Launch with `./start-ffxiv.sh`

Commands:

```bash
./setup.sh
./start-ffxiv.sh
```

Optional convenience step after setup:

```bash
./create-desktop-shortcut.sh
```

That creates a desktop launcher for the normal start script.

## Everyday Use

For normal day-to-day use, run:

```bash
./start-ffxiv.sh
```

If you created the desktop shortcut, you can launch the same flow from your applications menu instead.

`start-ffxiv.sh` starts the OTP helper in the background, launches the Steam FFXIV app (`39210`), waits for the XIVLauncher OTP listener, submits one OTP, and then exits.

## Troubleshooting

### Steam not found

- Make sure Steam is installed.
- Make sure the `steam` command is available in your `PATH`.
- This project only supports the Steam launch flow for FFXIV.

### OTP not autofilling

- Start with `./start-ffxiv.sh` instead of launching pieces manually.
- Make sure XIVLauncher is open on the OTP prompt.
- Wait for the launcher login flow to reach the point where the OTP listener is active.
- Check the current run log at `~/.local/state/xivl-otp-helper/helper.log` unless `XDG_STATE_HOME` is set.

### Forgot to enable the XIVLauncher OTP macro setting

- Open XIVLauncher settings.
- Enable `Use XIVLauncher authenticator/OTP macros`.
- Re-open the OTP prompt and try again.

### Invalid or wrong secret

- Re-run `./setup.sh` and paste the Base32 TOTP secret carefully.
- Remove spaces or accidental extra characters if needed.
- If needed, test with `XIVL_OTP_SECRET` first in the advanced section below.

### Desktop shortcut creation issues

- Re-run `./create-desktop-shortcut.sh` from the project directory.
- The shortcut is written to `~/.local/share/applications/final-fantasy-xiv-online.desktop`.
- If no suitable icon is found, the shortcut can still be created without one.

## Advanced Usage

The helper checks for the TOTP secret in this order:

1. `XIVL_OTP_SECRET`
2. `~/.config/xivl-otp-helper/config.json`

Environment variable example:

```bash
export XIVL_OTP_SECRET='BASE32SECRETGOESHERE'
./start-ffxiv.sh
```

Raw helper commands:

```bash
python3 xivl_otp_helper.py --once --verbose
python3 xivl_otp_helper.py --watch --verbose
python3 xivl_otp_helper.py --autofill-once --verbose
python3 xivl_otp_helper.py --watch --config ~/.config/xivl-otp-helper/config.json --interval 2
```

Use `--once` to try a single submission against an already-open listener, `--watch` to keep polling, and `--autofill-once` for the normal wait-submit-exit behavior used by `start-ffxiv.sh`.

## Developer / Technical Details

### Config and state files

- Config file: `~/.config/xivl-otp-helper/config.json`
- Log file: `~/.local/state/xivl-otp-helper/helper.log` unless `XDG_STATE_HOME` is set

`./setup.sh` securely prompts for your Base32 TOTP secret, asks you to enter it twice, validates it, writes the config automatically, and sets permissions to `0600`.

Config file shape:

```json
{
  "secret": "BASE32SECRETGOESHERE"
}
```

Example file:

[`config.json.example`](/home/xeltor/Projects/xivl-otp-helper/config.json.example)

### Implementation notes

- `xivl_otp_helper.py` generates RFC 6238 6-digit TOTP codes locally with the Python standard library.
- Generated OTP codes are never written to disk.
- The helper reads the secret from `XIVL_OTP_SECRET` or the local JSON config file.
- `start-ffxiv.sh` truncates the helper log on each run so old output does not mix with the current run.
- Steam must already be set up on your system to launch FFXIV the way you normally use it.
- This helper uses Python standard library modules only.

### Listener contract details

- The helper detects the XIVLauncher listener at `http://127.0.0.1:4646/`.
- It expects the root endpoint to return an XIVLauncher banner with `app` set to `XIVLauncher` and a `version` beginning with `core-`, or equivalent body text.
- It submits the current code to `http://127.0.0.1:4646/ffxivlauncher/<6-digit-code>`.
- It avoids resending the same code repeatedly during the same listener session.
- `--autofill-once` exits non-zero if the listener never appears before timeout.

### Desktop shortcut behavior

`./create-desktop-shortcut.sh` creates `~/.local/share/applications/final-fantasy-xiv-online.desktop`. When possible, it installs the bundled XIVLauncher SVG icon into `~/.local/share/icons/hicolor/scalable/apps/`; otherwise it falls back to a local icon file, an icon name from an existing desktop entry, or no icon.

### Repo layout

- [`start-ffxiv.sh`](/home/xeltor/Projects/xivl-otp-helper/start-ffxiv.sh): normal launch flow
- [`setup.sh`](/home/xeltor/Projects/xivl-otp-helper/setup.sh): first-time secret setup
- [`create-desktop-shortcut.sh`](/home/xeltor/Projects/xivl-otp-helper/create-desktop-shortcut.sh): desktop launcher creation
- [`xivl_otp_helper.py`](/home/xeltor/Projects/xivl-otp-helper/xivl_otp_helper.py): OTP generation and listener submission

## Security Caveat

From the helper's perspective, it only talks to `127.0.0.1:4646`.

XIVLauncher `1.3.1` binds its OTP listener to `0.0.0.0:4646` in this version, not loopback-only. That means the launcher-side listener is broader than ideal even though this helper itself uses loopback only.
