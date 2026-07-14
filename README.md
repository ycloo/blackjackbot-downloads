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
verifies the published SHA-256 checksum, and installs into
`~/BlackjackBot/current`. Runtime captures, logs, and ledger data live in the
stable `~/BlackjackBot/output` directory; `current/output` links to that same
location, so replacing an installed release does not replace runtime evidence.

The install root is identified by `.blackjackbot-install`. After each
successful install, `.installed-archive.sha256` records the exact verified ZIP
digest. These internal files let the installed extension recognize a managed
release and compare it with the current public download without trusting the
contents of an arbitrary `current` directory.

The first update from an older installation moves it out of
`~/Library/Application Support/BlackjackBot` and leaves a compatibility link
there so Chrome can continue reloading the already registered unpacked
extension.

The native messaging host requires `python3`. On a Mac without Python 3,
macOS may offer to install Xcode Command Line Tools when the installer checks
for it; a separately installed Python 3 also works. The bundle installer pins
the detected interpreter's absolute path for Chrome.

After the first install:

1. Open `chrome://extensions` and enable Developer mode.
2. Choose **Load unpacked** and select `~/BlackjackBot/current/extension`.
3. Grant Accessibility permission to `~/Applications/BlackjackBotCompanion.app`.

After an update, click **Reload** for BlackjackBot on `chrome://extensions`.
The installer preserves a valid unchanged companion app, including its existing
macOS Accessibility approval. Only a release with a new companion revision, or
an installed app that fails validation, replaces it and may require enabling
Accessibility again.

Current releases check the public download each time **Start** is pressed. If
a newer verified bundle is available, the log says
`Extension outdated and updating now`, the bundle is installed, and automation
does not start. Open `chrome://extensions`, click **Reload** for BlackjackBot,
then press **Start** again. The version currently loaded by Chrome is shown
beside **Blackjack Auditor**.

Before the download check, Start verifies that the loaded panel, active
background worker, exact native-host code, and installed bundle identify the
same release.
A legacy worker or version mismatch blocks automation and leaves a durable
Reload requirement instead of continuing with mixed code.

An installation from before this update support was added cannot bootstrap the
feature from inside the old extension. Run the installer above once manually,
then click **Reload** for BlackjackBot on `chrome://extensions`; subsequent
releases can be downloaded when **Start** performs its update check.

To pin a release:

```bash
curl -fsSL https://raw.githubusercontent.com/ycloo/blackjackbot-downloads/main/install-latest.sh \
  | BLACKJACKBOT_VERSION=v0.1.24 bash
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
