# BlackjackBot Downloads

Public, tokenless macOS release downloads for BlackjackBot. The private source
repository is not mirrored here.

## Install or Update

The shortest install command is:

```bash
curl -fsSL https://raw.githubusercontent.com/ycloo/blackjackbot-downloads/main/install-latest.sh | bash
```

For an inspect-then-run flow:

```bash
curl -fsSLO https://raw.githubusercontent.com/ycloo/blackjackbot-downloads/main/install-latest.sh
less install-latest.sh
bash install-latest.sh
```

The installer uses macOS base tools. It downloads the latest public ZIP,
verifies the published SHA-256 checksum, installs into
`~/Library/Application Support/BlackjackBot/current`, and preserves that
installation's `output/` directory during updates.

The native messaging host requires `python3`. On a Mac without Python 3,
macOS may offer to install Xcode Command Line Tools when the installer checks
for it; a separately installed Python 3 also works. The bundle installer pins
the detected interpreter's absolute path for Chrome.

After the first install:

1. Open `chrome://extensions` and enable Developer mode.
2. Choose **Load unpacked** and select `~/Library/Application Support/BlackjackBot/current/extension`.
3. Grant Accessibility permission to `~/Applications/BlackjackBotCompanion.app`.

After an update, click **Reload** for BlackjackBot on `chrome://extensions`.
If macOS no longer shows the companion as enabled under Accessibility, re-add
or re-enable it before running automation.

To pin a release:

```bash
curl -fsSL https://raw.githubusercontent.com/ycloo/blackjackbot-downloads/main/install-latest.sh \
  | BLACKJACKBOT_VERSION=v0.1.3 bash
```

## Security Scope

- Release checksums are published beside each ZIP and verified before the bundle installer executes. This detects a corrupted or mismatched download; it is not a substitute for reviewing a release from an account you trust.
- The companion app is universal (`arm64` and `x86_64`) and ad-hoc signed. It is not Developer ID signed or notarized and currently targets macOS 15 or newer.
- Accessibility permission lets the companion app send mouse clicks.
- The unpacked extension requests broad browser permissions, including scripting, tabs, native messaging, and access to all URLs.
- Automated withdrawal support can submit real withdrawal transactions in an already logged-in casino account. It is disabled by default and requires explicit per-site and per-card authorization.
- The public ZIP necessarily exposes the unpacked extension's JavaScript source.

Review the installer and release checksum before installing on a machine that
handles sensitive accounts.
