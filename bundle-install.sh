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

fail() {
  echo "error: $*" >&2
  exit 1
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
mkdir -p "$HOME/Applications"
rm -rf "$app_dest"
cp -R "$app_src" "$app_dest"
chmod +x "$app_dest/Contents/MacOS/"* 2>/dev/null || true

if command -v codesign >/dev/null 2>&1; then
  codesign --verify --deep --strict "$app_dest" \
    || fail "the installed companion app failed signature verification"
fi
echo "Installed companion app: $app_dest"

cat <<EOF

Two manual steps remain:

  1. Open chrome://extensions, enable Developer mode, choose Load unpacked,
     and select:
       $BUNDLE_DIR/extension

  2. In System Settings > Privacy & Security > Accessibility, add or enable:
       $app_dest

Confirm that Chrome shows this extension ID:
  $extension_id
EOF
