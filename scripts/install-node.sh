#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_DIR=$(cd -- "$SCRIPT_DIR/.." && pwd)
# Path is resolved from this checkout at runtime.
# shellcheck disable=SC1090,SC1091
source "$REPO_DIR/config/versions.env"

NODE_DIR="/opt/node-$NODE_VERSION-linux-x64"
NODE_ARCHIVE="node-$NODE_VERSION-linux-x64.tar.xz"
NODE_URL="https://nodejs.org/dist/$NODE_VERSION/$NODE_ARCHIVE"

if [[ ${EUID} -ne 0 ]]; then
  echo "Run this script as root." >&2
  exit 1
fi

if [[ $(dpkg --print-architecture) != amd64 ]]; then
  echo "This pinned installer supports Debian amd64 only." >&2
  exit 1
fi

if [[ ! -x "$NODE_DIR/bin/node" ]]; then
  node_tmp=$(mktemp -d)
  trap 'rm -rf -- "$node_tmp"' EXIT
  curl --proto '=https' --tlsv1.2 --fail --location --silent --show-error \
    --output "$node_tmp/$NODE_ARCHIVE" "$NODE_URL"
  printf '%s  %s\n' "$NODE_LINUX_X64_SHA256" "$node_tmp/$NODE_ARCHIVE" | sha256sum --check --status
  tar --extract --xz --file "$node_tmp/$NODE_ARCHIVE" --directory /opt
  rm -rf -- "$node_tmp"
  trap - EXIT
fi

if [[ -e /opt/node && ! -L /opt/node ]]; then
  echo "/opt/node exists and is not a symlink; refusing to replace it." >&2
  exit 1
fi
ln -sfn -- "$NODE_DIR" /opt/node
/opt/node/bin/node --version
