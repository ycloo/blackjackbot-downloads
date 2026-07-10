#!/usr/bin/env bash
set -euo pipefail
umask 077

REPOSITORY="ycloo/blackjackbot-downloads"
ASSET_NAME="blackjackbot-macos.zip"
CHECKSUM_NAME="${ASSET_NAME}.sha256"
VERSION="${BLACKJACKBOT_VERSION:-latest}"
ROOT_MARKER_NAME=".blackjackbot-install"
ROOT_MARKER_CONTENT="blackjackbot-install-v1"
MIGRATION_PENDING_NAME=".legacy-migration-pending"
MIGRATION_PENDING_CONTENT="blackjackbot-legacy-migration-v1"
INSTALLED_CHECKSUM_NAME=".installed-archive.sha256"
SEMVER_CORE_RE='(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)'
VERSION_TAG_RE="^v${SEMVER_CORE_RE}$"
ARCHIVE_ROOT_RE="^blackjackbot-v${SEMVER_CORE_RE}$"
CHECKSUM_VERSION_RE="^version=v${SEMVER_CORE_RE}$"

fail() {
  echo "error: $*" >&2
  exit 1
}

[ "$(uname -s)" = "Darwin" ] || fail "BlackjackBot currently supports macOS only"
[ -n "${HOME:-}" ] || fail "HOME is not set"
[ -d "$HOME" ] || fail "HOME does not point to a directory"

DEFAULT_INSTALL_ROOT="$HOME/BlackjackBot"
LEGACY_INSTALL_ROOT="$HOME/Library/Application Support/BlackjackBot"
CUSTOM_INSTALL_ROOT=0
if [ "${BLACKJACKBOT_INSTALL_ROOT+x}" = "x" ]; then
  INSTALL_ROOT="$BLACKJACKBOT_INSTALL_ROOT"
  CUSTOM_INSTALL_ROOT=1
else
  INSTALL_ROOT="$DEFAULT_INSTALL_ROOT"
fi
CURRENT_DIR="$INSTALL_ROOT/current"
ROOT_MARKER_PATH="$INSTALL_ROOT/$ROOT_MARKER_NAME"
MIGRATION_PENDING_PATH="$INSTALL_ROOT/$MIGRATION_PENDING_NAME"
INSTALLED_CHECKSUM_PATH="$INSTALL_ROOT/$INSTALLED_CHECKSUM_NAME"
OUTPUT_DIR="$INSTALL_ROOT/output"
[ -n "$INSTALL_ROOT" ] && [ "$INSTALL_ROOT" != "/" ] || fail "unsafe install root"
case "$INSTALL_ROOT" in
  /*) ;;
  *) fail "install root must be an absolute path" ;;
esac

if [ "$VERSION" = "latest" ]; then
  RELEASE_PATH="latest/download"
elif [[ "$VERSION" =~ $VERSION_TAG_RE ]]; then
  RELEASE_PATH="download/$VERSION"
else
  fail "BLACKJACKBOT_VERSION must be 'latest' or a tag such as v0.1.3"
fi

for command_name in curl shasum ditto unzip awk mktemp tr find ln readlink cmp cp; do
  command -v "$command_name" >/dev/null 2>&1 || fail "required command not found: $command_name"
done
[ -x /usr/bin/shlock ] || fail "required command not found: /usr/bin/shlock"

BASE_URL="https://github.com/$REPOSITORY/releases/$RELEASE_PATH"

file_has_exact_line() {
  local path="$1"
  local expected="$2"
  [ -f "$path" ] && [ ! -L "$path" ] \
    && LC_ALL=C cmp -s "$path" <(printf '%s\n' "$expected")
}

write_fixed_file_atomically() {
  local path="$1"
  local value="$2"
  local temporary_path="${path}.new.$$"

  [ ! -e "$temporary_path" ] && [ ! -L "$temporary_path" ] \
    || fail "temporary state path already exists: $temporary_path"
  printf '%s\n' "$value" > "$temporary_path"
  chmod 600 "$temporary_path"
  mv "$temporary_path" "$path"
}

bundle_is_blackjackbot() {
  local bundle_dir="$1"
  local directory_path
  local file_path

  [ -d "$bundle_dir" ] && [ ! -L "$bundle_dir" ] || return 1
  for directory_path in \
    "$bundle_dir/extension" \
    "$bundle_dir/native" \
    "$bundle_dir/BlackjackBotCompanion.app" \
    "$bundle_dir/BlackjackBotCompanion.app/Contents" \
    "$bundle_dir/BlackjackBotCompanion.app/Contents/MacOS"; do
    [ -d "$directory_path" ] && [ ! -L "$directory_path" ] || return 1
  done
  for file_path in \
    "$bundle_dir/install.sh" \
    "$bundle_dir/extension/manifest.json" \
    "$bundle_dir/native/native_host.py" \
    "$bundle_dir/BlackjackBotCompanion.app/Contents/Info.plist" \
    "$bundle_dir/BlackjackBotCompanion.app/Contents/MacOS/BlackjackBotCompanion"; do
    [ -f "$file_path" ] && [ ! -L "$file_path" ] || return 1
  done
}

managed_output_link_is_valid() {
  local bundle_dir="$1"
  [ -L "$bundle_dir/output" ] && [ "$(readlink "$bundle_dir/output")" = "../output" ]
}

ensure_root_marker() {
  if [ -e "$ROOT_MARKER_PATH" ] || [ -L "$ROOT_MARKER_PATH" ]; then
    file_has_exact_line "$ROOT_MARKER_PATH" "$ROOT_MARKER_CONTENT" \
      || fail "install root has an invalid ownership marker: $ROOT_MARKER_PATH"
  else
    write_fixed_file_atomically "$ROOT_MARKER_PATH" "$ROOT_MARKER_CONTENT"
  fi
}

create_legacy_compatibility_root() {
  local library_dir="$HOME/Library"
  local application_support_dir="$library_dir/Application Support"
  local directory_path

  for directory_path in "$library_dir" "$application_support_dir"; do
    [ ! -L "$directory_path" ] \
      || fail "legacy compatibility parent must not be a symbolic link: $directory_path"
    if [ -e "$directory_path" ] && [ ! -d "$directory_path" ]; then
      fail "legacy compatibility parent is not a directory: $directory_path"
    fi
  done
  mkdir -p "$LEGACY_INSTALL_ROOT" \
    || fail "could not create the legacy compatibility directory"
  chmod 700 "$LEGACY_INSTALL_ROOT"
}

finish_legacy_migration() {
  local legacy_current="$LEGACY_INSTALL_ROOT/current"

  [ -d "$INSTALL_ROOT" ] && [ ! -L "$INSTALL_ROOT" ] \
    || fail "pending legacy migration has no safe destination root"
  file_has_exact_line "$MIGRATION_PENDING_PATH" "$MIGRATION_PENDING_CONTENT" \
    || fail "legacy migration marker is invalid: $MIGRATION_PENDING_PATH"
  bundle_is_blackjackbot "$CURRENT_DIR" \
    || fail "pending legacy migration does not contain a BlackjackBot bundle"
  ensure_root_marker

  if [ -L "$LEGACY_INSTALL_ROOT" ]; then
    fail "legacy install root must not be a symbolic link: $LEGACY_INSTALL_ROOT"
  fi
  if [ ! -e "$LEGACY_INSTALL_ROOT" ]; then
    create_legacy_compatibility_root
  elif [ ! -d "$LEGACY_INSTALL_ROOT" ]; then
    fail "legacy compatibility path is not a directory: $LEGACY_INSTALL_ROOT"
  fi

  if [ -L "$legacy_current" ]; then
    [ "$(readlink "$legacy_current")" = "$CURRENT_DIR" ] \
      || fail "legacy compatibility link points somewhere unexpected: $legacy_current"
  elif [ -e "$legacy_current" ]; then
    fail "legacy compatibility path already exists and is not a symbolic link"
  else
    [ -z "$(find "$LEGACY_INSTALL_ROOT" -mindepth 1 -maxdepth 1 -print -quit)" ] \
      || fail "legacy compatibility directory is not empty: $LEGACY_INSTALL_ROOT"
    ln -s "$CURRENT_DIR" "$legacy_current" \
      || fail "could not create the legacy Chrome compatibility link"
  fi

  rm "$MIGRATION_PENDING_PATH"
}

migrate_legacy_install() {
  local legacy_current="$LEGACY_INSTALL_ROOT/current"
  local legacy_pending="$LEGACY_INSTALL_ROOT/$MIGRATION_PENDING_NAME"

  [ "$CUSTOM_INSTALL_ROOT" -eq 0 ] || return 0

  if [ -e "$MIGRATION_PENDING_PATH" ] || [ -L "$MIGRATION_PENDING_PATH" ]; then
    finish_legacy_migration
    echo "Completed interrupted migration to: $INSTALL_ROOT"
    return 0
  fi

  if [ -L "$LEGACY_INSTALL_ROOT" ]; then
    fail "legacy install root must not be a symbolic link: $LEGACY_INSTALL_ROOT"
  fi
  if [ -L "$legacy_current" ]; then
    [ "$(readlink "$legacy_current")" = "$CURRENT_DIR" ] \
      || fail "legacy compatibility link points somewhere unexpected: $legacy_current"
    return 0
  fi
  [ -d "$legacy_current" ] || return 0

  bundle_is_blackjackbot "$legacy_current" \
    || fail "legacy current directory is not a BlackjackBot release: $legacy_current"

  if [ -e "$INSTALL_ROOT" ] || [ -L "$INSTALL_ROOT" ]; then
    fail "both legacy and home-directory installs exist; move one aside before updating"
  fi
  if [ -e "$LEGACY_INSTALL_ROOT/.install.lock" ] \
    || [ -L "$LEGACY_INSTALL_ROOT/.install.lock" ]; then
    fail "a legacy install may still be running; remove its lock only when no installer is active"
  fi

  if [ -e "$legacy_pending" ] || [ -L "$legacy_pending" ]; then
    file_has_exact_line "$legacy_pending" "$MIGRATION_PENDING_CONTENT" \
      || fail "legacy migration marker is invalid: $legacy_pending"
  else
    write_fixed_file_atomically "$legacy_pending" "$MIGRATION_PENDING_CONTENT"
  fi
  mv "$LEGACY_INSTALL_ROOT" "$INSTALL_ROOT" \
    || fail "could not move the legacy installation to $INSTALL_ROOT"
  finish_legacy_migration
  echo "Migrated existing installation to: $INSTALL_ROOT"
}

migrate_legacy_install

if [ -L "$INSTALL_ROOT" ]; then
  fail "install root must not be a symbolic link: $INSTALL_ROOT"
fi
if [ -e "$INSTALL_ROOT" ] && [ ! -d "$INSTALL_ROOT" ]; then
  fail "install root exists and is not a directory: $INSTALL_ROOT"
fi
mkdir -p "$INSTALL_ROOT"
chmod 700 "$INSTALL_ROOT"

if [ -e "$ROOT_MARKER_PATH" ] || [ -L "$ROOT_MARKER_PATH" ]; then
  file_has_exact_line "$ROOT_MARKER_PATH" "$ROOT_MARKER_CONTENT" \
    || fail "install root has an invalid ownership marker: $ROOT_MARKER_PATH"
elif bundle_is_blackjackbot "$CURRENT_DIR"; then
  ensure_root_marker
elif [ -n "$(find "$INSTALL_ROOT" -mindepth 1 -maxdepth 1 -print -quit)" ]; then
  fail "install root exists and is not a BlackjackBot installation: $INSTALL_ROOT"
else
  ensure_root_marker
fi

if [ -e "$CURRENT_DIR" ] || [ -L "$CURRENT_DIR" ]; then
  bundle_is_blackjackbot "$CURRENT_DIR" \
    || fail "current directory is not a BlackjackBot release: $CURRENT_DIR"
fi
if [ -e "$MIGRATION_PENDING_PATH" ] || [ -L "$MIGRATION_PENDING_PATH" ]; then
  fail "unexpected pending migration marker: $MIGRATION_PENDING_PATH"
fi
if [ -L "$INSTALLED_CHECKSUM_PATH" ]; then
  fail "installed checksum record must not be a symbolic link: $INSTALLED_CHECKSUM_PATH"
fi

LOCK_DIR="$INSTALL_ROOT/.install.lock"
LOCK_OWNER_PATH="$LOCK_DIR/owner.pid"
RECOVERY_CLAIM_PATH="$LOCK_DIR/recovery.pid"
STAGED_DIR="$INSTALL_ROOT/.current.new.$$"
BACKUP_DIR="$INSTALL_ROOT/.current.previous.$$"
STATE_TEMP_PATH="${INSTALLED_CHECKSUM_PATH}.new.$$"
TEMP_DIR=""
TRANSACTION_ACTIVE=0
HAD_BACKUP=0
RECOVERY_CLAIMED=0
INSTALL_ARGS=("$@")

run_bundle_installer() {
  installer_path="$1"
  if [ "${#INSTALL_ARGS[@]}" -gt 0 ]; then
    bash "$installer_path" "${INSTALL_ARGS[@]}"
  else
    bash "$installer_path"
  fi
}

prepare_stable_output() {
  if [ -L "$OUTPUT_DIR" ]; then
    fail "managed output directory must not be a symbolic link: $OUTPUT_DIR"
  fi
  if [ -e "$OUTPUT_DIR" ] && [ ! -d "$OUTPUT_DIR" ]; then
    fail "managed output path is not a directory: $OUTPUT_DIR"
  fi

  if [ -L "$CURRENT_DIR/output" ]; then
    managed_output_link_is_valid "$CURRENT_DIR" \
      || fail "current output link does not point to the managed output directory"
    [ -d "$OUTPUT_DIR" ] \
      || fail "current output link has no managed output directory"
  elif [ -d "$CURRENT_DIR/output" ]; then
    [ -z "$(find "$CURRENT_DIR/output" -type l -print -quit)" ] \
      || fail "current output directory must not contain symbolic links"
    [ ! -e "$OUTPUT_DIR" ] \
      || fail "both current and managed output directories exist; refusing to merge them"
    mv "$CURRENT_DIR/output" "$OUTPUT_DIR"
    ln -s ../output "$CURRENT_DIR/output"
  elif [ -e "$CURRENT_DIR/output" ]; then
    fail "current output path is not a directory or managed link"
  else
    mkdir -p "$OUTPUT_DIR"
    if [ -d "$CURRENT_DIR" ]; then
      ln -s ../output "$CURRENT_DIR/output"
    fi
  fi

  mkdir -p "$OUTPUT_DIR"
  [ -z "$(find "$OUTPUT_DIR" -type l -print -quit)" ] \
    || fail "managed output directory must not contain symbolic links"
  chmod -R go-rwx "$OUTPUT_DIR"
}

seed_missing_output() {
  local source_root="$1"
  local source_path
  local relative_path
  local destination_path

  while IFS= read -r -d '' source_path; do
    relative_path="${source_path#"$source_root/"}"
    destination_path="$OUTPUT_DIR/$relative_path"
    if [ -d "$source_path" ] && [ ! -L "$source_path" ]; then
      if [ -e "$destination_path" ] || [ -L "$destination_path" ]; then
        [ -d "$destination_path" ] && [ ! -L "$destination_path" ] \
          || fail "release output directory conflicts with runtime data: $relative_path"
      elif ! mkdir "$destination_path" 2>/dev/null; then
        [ -d "$destination_path" ] && [ ! -L "$destination_path" ] \
          || fail "could not create release output directory: $relative_path"
      fi
    elif [ -f "$source_path" ] && [ ! -L "$source_path" ]; then
      if [ -e "$destination_path" ] || [ -L "$destination_path" ]; then
        [ -f "$destination_path" ] && [ ! -L "$destination_path" ] \
          || fail "release output file conflicts with runtime data: $relative_path"
      elif ! cp -n "$source_path" "$destination_path"; then
        # A runtime writer may have won the create race. Preserve that file.
        [ -f "$destination_path" ] && [ ! -L "$destination_path" ] \
          || fail "could not seed release output file: $relative_path"
      fi
    else
      fail "release output contains an unsupported file type: $relative_path"
    fi
  done < <(find "$source_root" -mindepth 1 -print0)
}

recover_abandoned_install() {
  local owner_pid
  local owner_line_count
  local stale_staged_dir
  local stale_backup_dir

  [ -d "$LOCK_DIR" ] && [ ! -L "$LOCK_DIR" ] \
    || fail "install lock is not a safe directory: $LOCK_DIR"
  [ -f "$LOCK_OWNER_PATH" ] && [ ! -L "$LOCK_OWNER_PATH" ] \
    || fail "install lock has no valid owner record: $LOCK_OWNER_PATH"
  if [ -e "$RECOVERY_CLAIM_PATH" ] || [ -L "$RECOVERY_CLAIM_PATH" ]; then
    [ -f "$RECOVERY_CLAIM_PATH" ] && [ ! -L "$RECOVERY_CLAIM_PATH" ] \
      || fail "abandoned-install recovery claim is unsafe: $RECOVERY_CLAIM_PATH"
  fi
  [ -z "$(find "$LOCK_DIR" -mindepth 1 -maxdepth 1 ! -name 'owner.pid' ! -name 'recovery.pid' -print -quit)" ] \
    || fail "install lock contains unexpected state: $LOCK_DIR"

  owner_line_count="$(LC_ALL=C awk 'END { print NR }' "$LOCK_OWNER_PATH")"
  owner_pid="$(LC_ALL=C awk 'NR == 1 { print }' "$LOCK_OWNER_PATH")"
  [ "$owner_line_count" = "1" ] && [[ "$owner_pid" =~ ^[1-9][0-9]*$ ]] \
    || fail "install lock owner is invalid: $LOCK_OWNER_PATH"
  if kill -0 "$owner_pid" 2>/dev/null; then
    fail "another install is still running with process $owner_pid"
  fi
  if ! /usr/bin/shlock -f "$RECOVERY_CLAIM_PATH" -p "$$"; then
    fail "another installer is recovering the abandoned installation"
  fi
  RECOVERY_CLAIMED=1
  file_has_exact_line "$LOCK_OWNER_PATH" "$owner_pid" \
    || fail "install lock owner changed while recovery was being claimed"
  if kill -0 "$owner_pid" 2>/dev/null; then
    fail "install lock owner became active while recovery was being claimed"
  fi

  stale_staged_dir="$INSTALL_ROOT/.current.new.$owner_pid"
  stale_backup_dir="$INSTALL_ROOT/.current.previous.$owner_pid"
  if [ -e "$stale_staged_dir" ] || [ -L "$stale_staged_dir" ]; then
    bundle_is_blackjackbot "$stale_staged_dir" \
      || fail "abandoned staged directory is not a BlackjackBot release: $stale_staged_dir"
  fi
  if [ -e "$stale_backup_dir" ] || [ -L "$stale_backup_dir" ]; then
    bundle_is_blackjackbot "$stale_backup_dir" \
      || fail "abandoned backup directory is not a BlackjackBot release: $stale_backup_dir"
    if [ -e "$CURRENT_DIR" ] || [ -L "$CURRENT_DIR" ]; then
      bundle_is_blackjackbot "$CURRENT_DIR" \
        || fail "current directory is unsafe during abandoned-install recovery: $CURRENT_DIR"
      rm -rf "$CURRENT_DIR"
    fi
    mv "$stale_backup_dir" "$CURRENT_DIR" \
      || fail "could not restore the previous release from $stale_backup_dir"
    run_bundle_installer "$CURRENT_DIR/install.sh" \
      || fail "the restored release could not be re-registered"
  elif [ -e "$CURRENT_DIR" ] || [ -L "$CURRENT_DIR" ]; then
    bundle_is_blackjackbot "$CURRENT_DIR" \
      || fail "current directory is unsafe during abandoned-install recovery: $CURRENT_DIR"
    run_bundle_installer "$CURRENT_DIR/install.sh" \
      || fail "the interrupted release could not be re-registered"
  fi

  if [ -e "$stale_staged_dir" ]; then
    rm -rf "$stale_staged_dir"
  fi
  rm -f "$INSTALLED_CHECKSUM_PATH"
  write_fixed_file_atomically "$LOCK_OWNER_PATH" "$$"
  chmod 600 "$LOCK_OWNER_PATH"
  file_has_exact_line "$RECOVERY_CLAIM_PATH" "$$" \
    || fail "abandoned-install recovery claim changed unexpectedly"
  rm "$RECOVERY_CLAIM_PATH"
  RECOVERY_CLAIMED=0
  echo "Recovered an interrupted BlackjackBot installation."
}

release_recovery_claim_on_exit() {
  if [ "$RECOVERY_CLAIMED" -eq 1 ] \
    && file_has_exact_line "$RECOVERY_CLAIM_PATH" "$$"; then
    rm -f "$RECOVERY_CLAIM_PATH"
  fi
}
trap release_recovery_claim_on_exit EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  recover_abandoned_install
elif ! printf '%s\n' "$$" > "$LOCK_OWNER_PATH"; then
  rmdir "$LOCK_DIR" 2>/dev/null || true
  fail "could not record the install lock owner"
fi
chmod 600 "$LOCK_OWNER_PATH"

cleanup() {
  status=$?
  trap - EXIT HUP INT TERM
  set +e

  if [ "$TRANSACTION_ACTIVE" -eq 1 ]; then
    if [ "$HAD_BACKUP" -eq 1 ] && [ -d "$BACKUP_DIR" ] && [ ! -L "$BACKUP_DIR" ]; then
      rm -rf "$CURRENT_DIR"
      if mv "$BACKUP_DIR" "$CURRENT_DIR"; then
        run_bundle_installer "$CURRENT_DIR/install.sh" >/dev/null 2>&1 || true
        rm -f "$INSTALLED_CHECKSUM_PATH"
        echo "Previous BlackjackBot release restored after installation failure." >&2
      else
        echo "error: could not restore previous release from $BACKUP_DIR" >&2
      fi
    elif [ "$HAD_BACKUP" -eq 0 ]; then
      rm -rf "$CURRENT_DIR"
      rm -f "$INSTALLED_CHECKSUM_PATH"
    fi
  fi

  if [ -n "$TEMP_DIR" ]; then
    rm -rf "$TEMP_DIR"
  fi
  rm -rf "$STAGED_DIR"
  rm -f "$STATE_TEMP_PATH"
  if file_has_exact_line "$LOCK_OWNER_PATH" "$$"; then
    rm -f "$LOCK_OWNER_PATH"
    rmdir "$LOCK_DIR" 2>/dev/null || true
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

prepare_stable_output

TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/blackjackbot-install.XXXXXX")"
ARCHIVE_PATH="$TEMP_DIR/$ASSET_NAME"
CHECKSUM_PATH="$TEMP_DIR/$CHECKSUM_NAME"
ARCHIVE_LIST_PATH="$TEMP_DIR/archive-entries.txt"
EXTRACT_DIR="$TEMP_DIR/extracted"

echo "Downloading BlackjackBot ${VERSION}..."
curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 \
  "$BASE_URL/$ASSET_NAME" -o "$ARCHIVE_PATH"
curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 \
  "$BASE_URL/$CHECKSUM_NAME" -o "$CHECKSUM_PATH"

checksum_line_count="$(LC_ALL=C awk 'END { print NR }' "$CHECKSUM_PATH")"
case "$checksum_line_count" in
  1|2) ;;
  *) fail "release checksum file must contain one digest line and optional version metadata" ;;
esac
checksum_field_count="$(LC_ALL=C awk 'NR == 1 { print NF }' "$CHECKSUM_PATH")"
checksum_asset_name="$(LC_ALL=C awk 'NR == 1 { print $2 }' "$CHECKSUM_PATH")"
expected_checksum="$(LC_ALL=C awk 'NR == 1 { print $1 }' "$CHECKSUM_PATH" | LC_ALL=C tr '[:upper:]' '[:lower:]')"
[ "$checksum_field_count" = "2" ] && [ "$checksum_asset_name" = "$ASSET_NAME" ] \
  || fail "release checksum does not identify $ASSET_NAME"
actual_checksum="$(LC_ALL=C shasum -a 256 "$ARCHIVE_PATH" | LC_ALL=C awk '{ print $1 }')"
[[ "$expected_checksum" =~ ^[0-9a-f]{64}$ ]] \
  || fail "release checksum file does not contain a SHA-256 digest"
[ "$actual_checksum" = "$expected_checksum" ] || fail "release checksum mismatch"

checksum_version=""
if [ "$checksum_line_count" = "2" ]; then
  checksum_metadata="$(LC_ALL=C awk 'NR == 2 { print }' "$CHECKSUM_PATH")"
  [[ "$checksum_metadata" =~ $CHECKSUM_VERSION_RE ]] \
    || fail "release checksum version metadata is invalid"
  checksum_version="${checksum_metadata#version=}"
fi
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
  [[ "$entry_root" =~ $ARCHIVE_ROOT_RE ]] \
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
if [ -n "$checksum_version" ] \
  && [ "$archive_root" != "blackjackbot-$checksum_version" ]; then
  fail "release archive version $archive_root does not match checksum metadata $checksum_version"
fi

mkdir -p "$EXTRACT_DIR"
ditto -x -k "$ARCHIVE_PATH" "$EXTRACT_DIR"

RELEASE_DIR="$EXTRACT_DIR/$archive_root"
[ -d "$RELEASE_DIR" ] && [ ! -L "$RELEASE_DIR" ] \
  || fail "release archive root is missing or unsafe"
[ -z "$(find "$RELEASE_DIR" -type l -print -quit)" ] \
  || fail "release archive must not contain symbolic links"
bundle_is_blackjackbot "$RELEASE_DIR" \
  || fail "release archive does not contain a complete BlackjackBot bundle"

# Runtime evidence lives outside the version transaction at $OUTPUT_DIR. Keep a
# compatibility link in each bundle for tools and older loaded native hosts.
[ ! -L "$RELEASE_DIR/output" ] || fail "release output directory must not be a symbolic link"
mkdir -p "$RELEASE_DIR/output"
seed_missing_output "$RELEASE_DIR/output"
chmod -R go-rwx "$OUTPUT_DIR"
rm -rf "$RELEASE_DIR/output"
ln -s ../output "$RELEASE_DIR/output"

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

[ ! -L "$INSTALLED_CHECKSUM_PATH" ] \
  || fail "installed checksum record must not be a symbolic link"
write_fixed_file_atomically "$INSTALLED_CHECKSUM_PATH" "$actual_checksum"

TRANSACTION_ACTIVE=0
rm -rf "$BACKUP_DIR"

cat <<EOF

Installed at:
  $CURRENT_DIR

To update later, run this installer again. After an update, open
chrome://extensions and click Reload for BlackjackBot.
EOF
