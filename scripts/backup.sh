#!/usr/bin/env bash
set -euo pipefail

OOYE_DIR=/opt/ooye
BACKUP_ROOT=${1:-/var/backups/ooye}

if [[ ${EUID} -ne 0 ]]; then
  echo "Run this script as root." >&2
  exit 1
fi

if [[ ! -f "$OOYE_DIR/registration.yaml" ]]; then
  echo "OOYE has not been configured; registration.yaml is missing." >&2
  exit 1
fi

was_active=false
if systemctl is-active --quiet ooye.service; then
  was_active=true
  systemctl stop ooye.service
fi

restart_if_needed() {
  if [[ $was_active == true ]]; then
    systemctl start ooye.service
  fi
}
trap restart_if_needed EXIT

install -d -o root -g root -m 0700 "$BACKUP_ROOT"
timestamp=$(date --utc +%Y%m%dT%H%M%SZ)
archive="$BACKUP_ROOT/ooye-$timestamp.tar.gz"

files=(registration.yaml)
while IFS= read -r -d '' database_file; do
  files+=("${database_file#"$OOYE_DIR/"}")
done < <(find "$OOYE_DIR" -maxdepth 1 -type f -name 'ooye.db*' -print0)

tar --create --gzip --file "$archive" --directory "$OOYE_DIR" -- "${files[@]}"
chmod 0600 "$archive"
echo "Created stopped-service backup: $archive"
