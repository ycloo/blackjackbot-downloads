# BlackjackBot for macOS

This directory is a self-contained BlackjackBot release. It includes the
unpacked Chrome extension, native messaging host, and universal companion app.

## Install

Run the bundled installer from this directory:

```bash
bash install.sh
```

The public bootstrap normally places this directory at:

```text
~/Library/Application Support/BlackjackBot/current
```

Keep the installed directory in place. Chrome's native messaging manifest
points to its `native/native_host.py`, and runtime captures, logs, and ledger
records are written under its `output/` directory.

After the installer finishes:

1. Open `chrome://extensions` and enable Developer mode.
2. Choose **Load unpacked** and select the `extension` directory here.
3. Grant Accessibility permission to `~/Applications/BlackjackBotCompanion.app`.

The native messaging host requires `python3`. On a Mac without Python 3,
macOS may offer to install Xcode Command Line Tools when the installer checks
for it; a separately installed Python 3 also works. The installer pins the
detected interpreter's absolute path for Chrome.

## Update

Use the public bootstrap again rather than moving files by hand:

```bash
curl -fsSL https://raw.githubusercontent.com/ycloo/blackjackbot-downloads/main/install-latest.sh | bash
```

It verifies the release checksum and preserves the installed `output/`
directory. Then click **Reload** for BlackjackBot on `chrome://extensions`.
If macOS no longer shows the companion as enabled under Accessibility, re-add
or re-enable it before running automation.

## Security Scope

- The companion app is ad-hoc signed, not Developer ID signed or notarized,
  and currently targets macOS 15 or newer.
- Accessibility permission allows the companion app to send mouse clicks.
- The unpacked extension has broad browser permissions for scripting, tabs,
  native messaging, and all URLs.
- Automated withdrawal support can submit real withdrawal transactions in an
  already logged-in casino account. It is disabled by default and needs
  explicit per-site and per-card authorization.
- The extension's JavaScript source is visible in this bundle.

Review the files and published SHA-256 checksum before using BlackjackBot on a
machine that handles sensitive accounts.
