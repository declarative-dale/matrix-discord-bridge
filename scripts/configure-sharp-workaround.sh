#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_DIR=$(cd -- "$SCRIPT_DIR/.." && pwd)

OOYE_DIR=/opt/ooye
WORKAROUND_DIR=/usr/local/lib/ooye
WORKAROUND_FILE="$WORKAROUND_DIR/sharp-workaround.cjs"
ENV_FILE=/etc/ooye-security.env

if [[ ${EUID} -ne 0 ]]; then
  echo "Run this script as root." >&2
  exit 1
fi

if [[ ! -f "$OOYE_DIR/node_modules/sharp/package.json" ]]; then
  echo "Sharp is not installed under $OOYE_DIR." >&2
  exit 1
fi

sharp_version=$(/opt/node/bin/node -e '
  const fs = require("node:fs")
  const pkg = JSON.parse(fs.readFileSync("/opt/ooye/node_modules/sharp/package.json", "utf8"))
  process.stdout.write(pkg.version)
')

if "$SCRIPT_DIR/sharp-workaround-required.sh" "$sharp_version"; then
  install -d -o root -g root -m 0755 "$WORKAROUND_DIR"
  install -o root -g root -m 0644 "$REPO_DIR/security/sharp-workaround.cjs" "$WORKAROUND_FILE"
  printf 'NODE_OPTIONS=--require=%s\n' "$WORKAROUND_FILE" >"$ENV_FILE"
  chown root:root "$ENV_FILE"
  chmod 0644 "$ENV_FILE"
  echo "Enabled the Sharp decoder workaround for vulnerable sharp $sharp_version."
else
  rm -f -- "$ENV_FILE" "$WORKAROUND_FILE"
  rmdir --ignore-fail-on-non-empty "$WORKAROUND_DIR" 2>/dev/null || true
  echo "Sharp $sharp_version includes the compatible fix; removed the decoder workaround."
fi
