# xivl-otp-helper

`xivl_otp_helper.py` is a small local-only helper for XIVLauncher OTP autofill on Linux.

This project is:
- Linux only
- Steam only
- designed for users who already launch FFXIV from Steam

If you use XIVLauncher/XLM, Steam should already be configured on your machine the way you normally launch the game.

It:
- reads a Base32 TOTP seed from `XIVL_OTP_SECRET` or a local JSON config file
- generates RFC 6238 6-digit TOTP codes locally with the Python standard library
- detects the XIVLauncher OTP listener at `http://127.0.0.1:4646/`
- submits the current code to `http://127.0.0.1:4646/ffxivlauncher/<6-digit-code>`
- avoids resending the same code repeatedly during the same listener session

## Quick Start

Project path assumed below:

```bash
cd ~/Projects/xivl-otp-helper
```

1. Run `./setup.sh`
2. Enter your Base32 TOTP secret when prompted
3. In XIVLauncher, enable `Use XIVLauncher authenticator/OTP macros`
4. Start the normal flow with `./start-ffxiv.sh`

Normal user flow:

```bash
./start-ffxiv.sh
```

Desktop shortcut setup:

```bash
./create-desktop-shortcut.sh
```

That script:
- starts the OTP helper in the background
- launches the Steam FFXIV app (`39210`)
- waits for the OTP listener
- submits one OTP once
- exits the helper after a successful submission
- stops the helper if XIVLauncher exits before autofill completes

## Enable XIVLauncher OTP macros

In XIVLauncher, enable:

`Use XIVLauncher authenticator/OTP macros`

That is the setting which turns on the local OTP listener in XIVLauncher `1.3.1`.

## Setup

The helper is meant to run from:

```bash
~/Projects/xivl-otp-helper
```

First-time setup:

```bash
./setup.sh
```

`./setup.sh` will:

- securely prompt for your Base32 TOTP secret
- ask you to enter it twice for confirmation
- validate that it looks like Base32
- write `~/.config/xivl-otp-helper/config.json` automatically
- set the config permissions to `0600`

That creates:

```text
~/.config/xivl-otp-helper/config.json
```

The config file shape is:

```json
{
  "secret": "BASE32SECRETGOESHERE"
}
```

The repository includes this example file:

[`config.json.example`](/home/xeltor/Projects/xivl-otp-helper/config.json.example)

## Normal Usage

Use this for day-to-day launching:

```bash
./start-ffxiv.sh
```

If the helper config is missing, `start-ffxiv.sh` will tell you to run `./setup.sh` first.
`start-ffxiv.sh` launches FFXIV through Steam using app id `39210`.

`./create-desktop-shortcut.sh` creates `~/.local/share/applications/final-fantasy-xiv-online.desktop` and ships its own XIVLauncher icon from the repo. When possible, it copies that bundled SVG into `~/.local/share/icons/hicolor/scalable/apps/` before writing the desktop entry.

## Advanced Usage

The helper checks for the TOTP seed in this order:

1. `XIVL_OTP_SECRET`
2. `~/.config/xivl-otp-helper/config.json`

Environment variable example:

```bash
export XIVL_OTP_SECRET='BASE32SECRETGOESHERE'
./start-ffxiv.sh
```

Run once against an already-open OTP listener:

```bash
python3 xivl_otp_helper.py --once --verbose
```

Watch mode:

```bash
python3 xivl_otp_helper.py --watch --verbose
```

Autofill once, then exit:

```bash
python3 xivl_otp_helper.py --autofill-once --verbose
```

Watch mode with a custom config path and interval:

```bash
python3 xivl_otp_helper.py --watch --config ~/.config/xivl-otp-helper/config.json --interval 2
```

## Troubleshooting

### Listener not available at http://127.0.0.1:4646

- If you are using the normal flow, start with `./start-ffxiv.sh`.
- Make sure XIVLauncher is open on the OTP prompt.
- Make sure `Use XIVLauncher authenticator/OTP macros` is enabled in XIVLauncher.
- The helper polls `127.0.0.1:4646` and expects the XIVLauncher banner there before it submits anything.
- `--autofill-once` exits non-zero if the listener never appears before timeout.
- The helper log for the current run is written to `~/.local/state/xivl-otp-helper/helper.log` unless `XDG_STATE_HOME` is set.

### OTP macro setting not enabled in XIVLauncher

- Open XIVLauncher settings.
- Enable `Use XIVLauncher authenticator/OTP macros`.
- Re-open the OTP prompt and try `--once` or `--watch` again.

### Wrong or invalid Base32 secret

- Check that your secret is the TOTP seed in Base32 form.
- Remove spaces or accidental extra characters if needed.
- If the helper says the secret is invalid Base32, re-copy it carefully and test again with the environment variable first.

## Notes

- Generated OTP codes are never written to disk.
- This helper uses Python standard library modules only.
- The helper submits only to the local listener on `127.0.0.1:4646`.
- `start-ffxiv.sh` launches the helper first, then launches FFXIV through Steam.
- `start-ffxiv.sh` truncates the helper log each run so old output does not mix with the current run.
- Steam must already be set up on your system to launch FFXIV the way you normally use it.

## Security note

XIVLauncher `1.3.1` binds its OTP listener to `0.0.0.0:4646` in this version, not loopback-only.

From the helper's perspective, it talks only to `127.0.0.1:4646`.

That means the launcher-side listener is broader than ideal even though this helper itself uses loopback only. Users should understand that caveat before relying on it.
