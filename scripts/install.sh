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

if [[ $(dpkg --print-architecture) != amd64 ]]; then
  echo "This pinned installer supports Debian amd64 only." >&2
  exit 1
fi

if ! grep -qE '^VERSION_ID="?13"?$' /etc/os-release; then
  echo "This installer is intended for Debian 13." >&2
  exit 1
fi

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  build-essential \
  ca-certificates \
  curl \
  git \
  python3 \
  xz-utils

if ! id ooye >/dev/null 2>&1; then
  useradd --system --user-group --home-dir "$OOYE_DIR" --no-create-home --shell /usr/sbin/nologin ooye
fi
install -d -o ooye -g ooye -m 0700 "$OOYE_DIR"

"$SCRIPT_DIR/install-node.sh"

if [[ ! -d "$OOYE_DIR/.git" ]]; then
  if [[ -n $(find "$OOYE_DIR" -mindepth 1 -maxdepth 1 -print -quit) ]]; then
    echo "$OOYE_DIR exists and is not an OOYE Git checkout; refusing to overwrite it." >&2
    exit 1
  fi
  runuser -u ooye -- git clone --branch "$OOYE_VERSION" --depth 1 \
    https://gitdab.com/cadence/out-of-your-element.git "$OOYE_DIR"
fi

actual_commit=$(runuser -u ooye -- git -C "$OOYE_DIR" rev-parse HEAD)
if [[ $actual_commit != "$OOYE_COMMIT" ]]; then
  echo "OOYE checkout is $actual_commit, expected $OOYE_COMMIT; refusing to continue." >&2
  exit 1
fi

runuser -u ooye -- env PATH="/opt/node/bin:/usr/bin:/bin" \
  /opt/node/bin/npm --prefix "$OOYE_DIR" ci --omit=dev

"$SCRIPT_DIR/configure-sharp-workaround.sh"

install -o root -g root -m 0644 "$REPO_DIR/systemd/ooye.service" /etc/systemd/system/ooye.service
systemctl daemon-reload

echo
echo "OOYE $OOYE_VERSION and Node.js $NODE_VERSION are installed."
echo "The service is installed but not enabled or started."
echo "Continue with the interactive setup documented in README.md."
