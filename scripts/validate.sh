#!/usr/bin/env bash
set -euo pipefail

REPO_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$REPO_DIR"

for script in scripts/*.sh; do
  bash -n "$script"
done

if command -v shellcheck >/dev/null 2>&1; then
  shellcheck scripts/*.sh
fi

grep -q '^OOYE_VERSION=v' config/versions.env
grep -Eq '^OOYE_COMMIT=[0-9a-f]{40}$' config/versions.env
grep -Eq '^NODE_VERSION=v22\.' config/versions.env
grep -Eq '^NODE_LINUX_X64_SHA256=[0-9a-f]{64}$' config/versions.env
grep -Fq 'sharp.block({ operation: ["VipsForeignLoadNsgif", "VipsForeignLoadTiff", "VipsForeignLoadVips"] });' security/sharp-workaround.cjs
grep -q '^FIXED_VERSION=0.35.0$' scripts/sharp-workaround-required.sh
scripts/sharp-workaround-required.sh 0.34.5
if scripts/sharp-workaround-required.sh 0.35.0; then
  echo "The Sharp workaround must be disabled at the fixed version." >&2
  exit 1
fi

grep -q '^User=ooye$' systemd/ooye.service
grep -q '^WorkingDirectory=/opt/ooye$' systemd/ooye.service
grep -q '^EnvironmentFile=-/etc/ooye-security.env$' systemd/ooye.service
grep -q '^ExecStart=/opt/node/bin/node ' systemd/ooye.service
grep -q '^NoNewPrivileges=true$' systemd/ooye.service

if [[ ${CI:-false} == true ]] && command -v systemd-analyze >/dev/null 2>&1; then
  unit_tmp=$(mktemp --suffix=.service)
  trap 'rm -f -- "$unit_tmp"' EXIT
  sed \
    -e '/^ConditionPathExists=/d' \
    -e 's#^ExecStart=.*#ExecStart=/bin/true#' \
    systemd/ooye.service >"$unit_tmp"
  systemd-analyze verify "$unit_tmp"
  rm -f -- "$unit_tmp"
  trap - EXIT
fi

if command -v ruby >/dev/null 2>&1; then
  ruby -e 'require "yaml"; YAML.safe_load_file("coolify/ooye.yaml", aliases: false)'
fi

if git ls-files | grep -Eq '(^|/)(registration\.ya?ml|ooye\.db([.-].*)?|\.env)$'; then
  echo "An OOYE runtime secret or database file is tracked by Git." >&2
  exit 1
fi

echo "Repository validation passed."
