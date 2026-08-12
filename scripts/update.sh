#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_DIR=$(cd -- "$SCRIPT_DIR/.." && pwd)
# Path is resolved from this checkout at runtime.
# shellcheck disable=SC1090,SC1091
source "$REPO_DIR/config/versions.env"

OOYE_DIR=/opt/ooye

if [[ ${EUID} -ne 0 ]]; then
  echo "Run this script as root." >&2
  exit 1
fi

if [[ ! -d "$OOYE_DIR/.git" ]]; then
  echo "OOYE is not installed at $OOYE_DIR." >&2
  exit 1
fi

if [[ -n $(runuser -u ooye -- git -C "$OOYE_DIR" status --short --untracked-files=no) ]]; then
  echo "Tracked OOYE files have local changes; refusing to overwrite them." >&2
  exit 1
fi

"$SCRIPT_DIR/install-node.sh"

was_active=false
if systemctl is-active --quiet ooye.service; then
  was_active=true
fi

"$SCRIPT_DIR/backup.sh"
trap 'if [[ $was_active == true ]]; then systemctl start ooye.service; fi' EXIT
systemctl stop ooye.service 2>/dev/null || true

runuser -u ooye -- git -C "$OOYE_DIR" fetch --force --depth 1 origin \
  "refs/tags/$OOYE_VERSION:refs/tags/$OOYE_VERSION"
runuser -u ooye -- git -C "$OOYE_DIR" checkout --detach "$OOYE_COMMIT"

actual_commit=$(runuser -u ooye -- git -C "$OOYE_DIR" rev-parse HEAD)
if [[ $actual_commit != "$OOYE_COMMIT" ]]; then
  echo "OOYE checkout verification failed." >&2
  exit 1
fi

runuser -u ooye -- env PATH="/opt/node/bin:/usr/bin:/bin" \
  /opt/node/bin/npm --prefix "$OOYE_DIR" ci --omit=dev

"$SCRIPT_DIR/configure-sharp-workaround.sh"

if [[ $was_active == true ]]; then
  systemctl start ooye.service
fi
trap - EXIT

echo "Updated OOYE to $OOYE_VERSION ($OOYE_COMMIT)."
