#!/usr/bin/env bash
set -euo pipefail
umask 077

REPOSITORY="ycloo/blackjackbot-downloads"
ASSET_NAME="blackjackbot-macos.zip"
CHECKSUM_NAME="${ASSET_NAME}.sha256"
VERSION="${BLACKJACKBOT_VERSION:-latest}"

fail() {
  echo "error: $*" >&2
  exit 1
}

[ "$(uname -s)" = "Darwin" ] || fail "BlackjackBot currently supports macOS only"
[ -n "${HOME:-}" ] || fail "HOME is not set"
[ -d "$HOME" ] || fail "HOME does not point to a directory"

INSTALL_ROOT="${BLACKJACKBOT_INSTALL_ROOT:-$HOME/Library/Application Support/BlackjackBot}"
CURRENT_DIR="$INSTALL_ROOT/current"
[ -n "$INSTALL_ROOT" ] && [ "$INSTALL_ROOT" != "/" ] || fail "unsafe install root"
case "$INSTALL_ROOT" in
  /*) ;;
  *) fail "install root must be an absolute path" ;;
esac

if [ "$VERSION" = "latest" ]; then
  RELEASE_PATH="latest/download"
elif [[ "$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  RELEASE_PATH="download/$VERSION"
else
  fail "BLACKJACKBOT_VERSION must be 'latest' or a tag such as v0.1.3"
fi

for command_name in curl shasum ditto unzip awk mktemp tr find; do
  command -v "$command_name" >/dev/null 2>&1 || fail "required command not found: $command_name"
done

BASE_URL="https://github.com/$REPOSITORY/releases/$RELEASE_PATH"
if [ -L "$INSTALL_ROOT" ]; then
  fail "install root must not be a symbolic link: $INSTALL_ROOT"
fi
mkdir -p "$INSTALL_ROOT"
chmod 700 "$INSTALL_ROOT"

LOCK_DIR="$INSTALL_ROOT/.install.lock"
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  fail "another install may be running; remove $LOCK_DIR if no installer is active"
fi

TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/blackjackbot-install.XXXXXX")"
ARCHIVE_PATH="$TEMP_DIR/$ASSET_NAME"
CHECKSUM_PATH="$TEMP_DIR/$CHECKSUM_NAME"
ARCHIVE_LIST_PATH="$TEMP_DIR/archive-entries.txt"
EXTRACT_DIR="$TEMP_DIR/extracted"
STAGED_DIR="$INSTALL_ROOT/.current.new.$$"
BACKUP_DIR="$INSTALL_ROOT/.current.previous.$$"
TRANSACTION_ACTIVE=0
HAD_BACKUP=0
INSTALL_ARGS=("$@")

run_bundle_installer() {
  installer_path="$1"
  if [ "${#INSTALL_ARGS[@]}" -gt 0 ]; then
    bash "$installer_path" "${INSTALL_ARGS[@]}"
  else
    bash "$installer_path"
  fi
}

cleanup() {
  status=$?
  trap - EXIT HUP INT TERM
  set +e

  if [ "$TRANSACTION_ACTIVE" -eq 1 ]; then
    if [ "$HAD_BACKUP" -eq 1 ] && [ -d "$BACKUP_DIR" ] && [ ! -L "$BACKUP_DIR" ]; then
      rm -rf "$CURRENT_DIR"
      if mv "$BACKUP_DIR" "$CURRENT_DIR"; then
        run_bundle_installer "$CURRENT_DIR/install.sh" >/dev/null 2>&1 || true
        echo "Previous BlackjackBot release restored after installation failure." >&2
      else
        echo "error: could not restore previous release from $BACKUP_DIR" >&2
      fi
    elif [ "$HAD_BACKUP" -eq 0 ]; then
      rm -rf "$CURRENT_DIR"
    fi
  fi

  rm -rf "$TEMP_DIR" "$STAGED_DIR"
  rmdir "$LOCK_DIR" 2>/dev/null || true
  exit "$status"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

echo "Downloading BlackjackBot ${VERSION}..."
curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 \
  "$BASE_URL/$ASSET_NAME" -o "$ARCHIVE_PATH"
curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 \
  "$BASE_URL/$CHECKSUM_NAME" -o "$CHECKSUM_PATH"

expected_checksum="$(LC_ALL=C awk 'NF { print $1; exit }' "$CHECKSUM_PATH" | LC_ALL=C tr '[:upper:]' '[:lower:]')"
actual_checksum="$(LC_ALL=C shasum -a 256 "$ARCHIVE_PATH" | LC_ALL=C awk '{ print $1 }')"
[[ "$expected_checksum" =~ ^[0-9a-f]{64}$ ]] \
  || fail "release checksum file does not contain a SHA-256 digest"
[ "$actual_checksum" = "$expected_checksum" ] || fail "release checksum mismatch"
echo "Checksum verified: $actual_checksum"

archive_root=""
LC_ALL=C unzip -Z1 "$ARCHIVE_PATH" > "$ARCHIVE_LIST_PATH" \
  || fail "release archive directory could not be read"
while IFS= read -r entry; do
  [ -n "$entry" ] || fail "release archive contains an empty path"
  case "$entry" in
    /*|*\\*) fail "release archive contains an unsafe path: $entry" ;;
  esac
  case "/$entry/" in
    */../*|*/./*) fail "release archive contains an unsafe path: $entry" ;;
  esac

  entry_root="${entry%%/*}"
  [[ "$entry_root" =~ ^blackjackbot-v[0-9]+\.[0-9]+\.[0-9]+$ ]] \
    || fail "release archive has an unexpected root: $entry_root"
  if [ -z "$archive_root" ]; then
    archive_root="$entry_root"
  elif [ "$entry_root" != "$archive_root" ]; then
    fail "release archive must contain exactly one top-level directory"
  fi
done < "$ARCHIVE_LIST_PATH"
[ -n "$archive_root" ] || fail "release archive is empty"
if [ "$VERSION" != "latest" ] && [ "$archive_root" != "blackjackbot-$VERSION" ]; then
  fail "release archive version $archive_root does not match requested $VERSION"
fi

mkdir -p "$EXTRACT_DIR"
ditto -x -k "$ARCHIVE_PATH" "$EXTRACT_DIR"

RELEASE_DIR="$EXTRACT_DIR/$archive_root"
[ -d "$RELEASE_DIR" ] && [ ! -L "$RELEASE_DIR" ] \
  || fail "release archive root is missing or unsafe"
[ -f "$RELEASE_DIR/install.sh" ] && [ ! -L "$RELEASE_DIR/install.sh" ] \
  || fail "release archive does not contain a regular install.sh"
[ -z "$(find "$RELEASE_DIR" -type l -print -quit)" ] \
  || fail "release archive must not contain symbolic links"

# Keep runtime evidence across upgrades while replacing application files.
[ ! -L "$RELEASE_DIR/output" ] || fail "release output directory must not be a symbolic link"
mkdir -p "$RELEASE_DIR/output"
[ ! -L "$CURRENT_DIR" ] || fail "current installation must not be a symbolic link"
[ ! -L "$CURRENT_DIR/output" ] || fail "current output directory must not be a symbolic link"
if [ -d "$CURRENT_DIR/output" ]; then
  cp -R "$CURRENT_DIR/output/." "$RELEASE_DIR/output/"
fi
chmod -R go-rwx "$RELEASE_DIR/output"

rm -rf "$STAGED_DIR" "$BACKUP_DIR"
mv "$RELEASE_DIR" "$STAGED_DIR"
TRANSACTION_ACTIVE=1
if [ -d "$CURRENT_DIR" ]; then
  [ ! -L "$CURRENT_DIR" ] || fail "current installation must not be a symbolic link"
  HAD_BACKUP=1
  mv "$CURRENT_DIR" "$BACKUP_DIR"
fi
mv "$STAGED_DIR" "$CURRENT_DIR"

run_bundle_installer "$CURRENT_DIR/install.sh" \
  || fail "installation failed"

TRANSACTION_ACTIVE=0
rm -rf "$BACKUP_DIR"

cat <<EOF

Installed at:
  $CURRENT_DIR

To update later, run this installer again. After an update, open
chrome://extensions and click Reload for BlackjackBot.
EOF
