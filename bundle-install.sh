#!/usr/bin/env bash
# BlackjackBot release-bundle installer.
#
# Usage:
#   bash install.sh [EXTENSION_ID]
#   bash install.sh --extension-id EXTENSION_ID

set -euo pipefail
umask 077

HOST_NAME="com.yanchenglu.blackjackbot"
DEFAULT_EXTENSION_ID="hmdefbacdajknanbcdfeaefhpfnnapnf"
COMPANION_BUNDLE_ID="com.yanchenglu.blackjackbot.companion"
PLIST_BUDDY="/usr/libexec/PlistBuddy"

fail() {
  echo "error: $*" >&2
  exit 1
}

companion_plist_value() {
  "$PLIST_BUDDY" -c "Print :$2" "$1/Contents/Info.plist" 2>/dev/null || true
}

[ -n "${HOME:-}" ] || fail "HOME is not set"
[ -d "$HOME" ] || fail "HOME does not point to a directory"

BUNDLE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
extension_id="${BLACKJACKBOT_EXTENSION_ID:-$DEFAULT_EXTENSION_ID}"

while [ $# -gt 0 ]; do
  case "$1" in
    --extension-id)
      [ $# -ge 2 ] || fail "--extension-id requires a value"
      extension_id="$2"
      shift 2
      ;;
    --extension-id=*)
      extension_id="${1#*=}"
      shift
      ;;
    -h|--help)
      sed -n 's/^# \{0,1\}//p' "$0"
      exit 0
      ;;
    *)
      extension_id="$1"
      shift
      ;;
  esac
done

[[ "$extension_id" =~ ^[a-p]{32}$ ]] \
  || fail "invalid Chrome extension id: $extension_id"

native_host="$BUNDLE_DIR/native/native_host.py"
native_launcher="$BUNDLE_DIR/native/native_host_launcher.sh"
[ -f "$native_host" ] && [ ! -L "$native_host" ] \
  || fail "native host not found at $native_host"

python3_path="${BLACKJACKBOT_PYTHON3:-}"
if [ -z "$python3_path" ]; then
  python3_path="$(command -v python3 || true)"
fi
[ -n "$python3_path" ] \
  || fail "python3 is required; install Python 3 or Xcode Command Line Tools, then retry"
case "$python3_path" in
  /*) ;;
  *) fail "python3 path must be absolute" ;;
esac
[ -x "$python3_path" ] \
  || fail "python3 is required; install Python 3 or Xcode Command Line Tools, then retry"
if ! "$python3_path" -c 'import sys; sys.exit(0)' >/dev/null 2>&1; then
  fail "python3 could not run; install Python 3 or finish the Command Line Tools setup, then retry"
fi
if ! "$python3_path" "$native_host" </dev/null >/dev/null 2>&1; then
  fail "native host failed its Python startup check"
fi

printf '#!/bin/bash\nexec %q %q "$@"\n' "$python3_path" "$native_host" > "$native_launcher"
chmod 700 "$native_launcher"
case "$native_launcher" in
  *'"'*|*'\'*) fail "bundle path contains characters that cannot be registered safely" ;;
esac

echo "BlackjackBot install"
echo "  bundle:       $BUNDLE_DIR"
echo "  extension id: $extension_id"
echo "  python3:      $python3_path"
echo ""

manifest_dir="$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts"
manifest_path="$manifest_dir/$HOST_NAME.json"
mkdir -p "$manifest_dir"
cat > "$manifest_path" <<EOF
{
  "name": "$HOST_NAME",
  "description": "BlackjackBot native messaging host",
  "path": "$native_launcher",
  "type": "stdio",
  "allowed_origins": [
    "chrome-extension://$extension_id/"
  ]
}
EOF
chmod 644 "$manifest_path"
echo "Installed native messaging host manifest: $manifest_path"

app_src="$BUNDLE_DIR/BlackjackBotCompanion.app"
app_dest="$HOME/Applications/BlackjackBotCompanion.app"
[ -d "$app_src" ] && [ ! -L "$app_src" ] \
  || fail "companion app not found at $app_src"
[ -x "$PLIST_BUDDY" ] || fail "PlistBuddy is required to validate the companion app"

incoming_bundle_id="$(companion_plist_value "$app_src" CFBundleIdentifier)"
incoming_revision="$(companion_plist_value "$app_src" CFBundleVersion)"
incoming_build_id="$(companion_plist_value "$app_src" BlackjackBotCompanionBuildID)"
[ "$incoming_bundle_id" = "$COMPANION_BUNDLE_ID" ] \
  || fail "companion app has an unexpected bundle identifier: $incoming_bundle_id"
[[ "$incoming_revision" =~ ^[1-9][0-9]*$ ]] \
  || fail "companion app has an invalid revision: $incoming_revision"
[[ "$incoming_build_id" =~ ^[0-9a-f]{64}$ ]] \
  || fail "companion app has an invalid build ID"
if command -v codesign >/dev/null 2>&1; then
  codesign --verify --deep --strict "$app_src" \
    || fail "the bundled companion app failed signature verification"
fi

mkdir -p "$HOME/Applications"
preserve_companion=false
if [ -e "$app_dest" ] || [ -L "$app_dest" ]; then
  [ -d "$app_dest" ] && [ ! -L "$app_dest" ] \
    || fail "companion destination is not a safe app directory: $app_dest"
  installed_bundle_id="$(companion_plist_value "$app_dest" CFBundleIdentifier)"
  installed_revision="$(companion_plist_value "$app_dest" CFBundleVersion)"
  installed_build_id="$(companion_plist_value "$app_dest" BlackjackBotCompanionBuildID)"
  installed_signature_ok=true
  if command -v codesign >/dev/null 2>&1 \
    && ! codesign --verify --deep --strict "$app_dest" >/dev/null 2>&1; then
    installed_signature_ok=false
  fi
  if [ "$installed_signature_ok" = true ] \
    && [ "$installed_bundle_id" = "$COMPANION_BUNDLE_ID" ]; then
    if [ -n "$installed_build_id" ] && [ "$installed_build_id" = "$incoming_build_id" ]; then
      preserve_companion=true
    elif [ -z "$installed_build_id" ] && [ "$installed_revision" = "$incoming_revision" ]; then
      # v0.1.1-v0.1.7 shipped revision 1 without an explicit build ID.
      preserve_companion=true
    fi
  fi
fi

if [ "$preserve_companion" = true ]; then
  echo "Companion app unchanged (revision $incoming_revision); preserved Accessibility approval: $app_dest"
else
  app_stage="$HOME/Applications/.BlackjackBotCompanion.app.install.$$"
  [ ! -e "$app_stage" ] && [ ! -L "$app_stage" ] \
    || fail "temporary companion path already exists: $app_stage"
  cp -R "$app_src" "$app_stage"
  chmod +x "$app_stage/Contents/MacOS/"* 2>/dev/null || true
  # Strip the download quarantine before the app is ever launched. A quarantined
  # bundle triggers Gatekeeper App Translocation, which runs the companion from a
  # randomized read-only mount instead of $app_dest — that both breaks the
  # Accessibility grant (it is path-scoped) and collides with `open -n` relaunches
  # as EBUSY "Resource busy". Do this on the staged copy so it verifies clean.
  command -v xattr >/dev/null 2>&1 \
    && xattr -dr com.apple.quarantine "$app_stage" 2>/dev/null || true
  if command -v codesign >/dev/null 2>&1; then
    codesign --verify --deep --strict "$app_stage" \
      || { rm -rf "$app_stage"; fail "the staged companion app failed signature verification"; }
  fi
  rm -rf "$app_dest"
  mv "$app_stage" "$app_dest"
  echo "Installed companion app (revision $incoming_revision): $app_dest"
fi

cat <<EOF

Load or reload the extension in Chrome:

  1. Open chrome://extensions, enable Developer mode, choose Load unpacked,
     and select:
       $BUNDLE_DIR/extension
EOF

if [ "$preserve_companion" = true ]; then
  cat <<EOF
  2. Accessibility is unchanged. The existing companion app was preserved,
     so its current Privacy & Security approval remains in place.
EOF
else
  cat <<EOF
  2. In System Settings > Privacy & Security > Accessibility, add or enable:
       $app_dest
EOF
fi

cat <<EOF
Confirm that Chrome shows this extension ID:
  $extension_id
EOF
