#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_DIR=$(cd -- "$SCRIPT_DIR/.." && pwd)
VERSIONS_FILE="$REPO_DIR/config/versions.env"
# Path is resolved from this checkout at runtime.
# shellcheck disable=SC1090,SC1091
source "$VERSIONS_FILE"

for command_name in curl git jq sed sort; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Required command is missing: $command_name" >&2
    exit 1
  fi
done

release_json=$(curl --proto '=https' --tlsv1.2 --fail --location --silent --show-error \
  https://gitdab.com/api/v1/repos/cadence/out-of-your-element/releases/latest)
latest_ooye=$(jq -er 'select(.draft == false and .prerelease == false) | .tag_name' <<<"$release_json")
tag_refs=$(git ls-remote https://gitdab.com/cadence/out-of-your-element.git \
  "refs/tags/$latest_ooye" "refs/tags/$latest_ooye^{}")
latest_ooye_commit=$(awk '$2 ~ /\^\{\}$/ {print $1; exit}' <<<"$tag_refs")
if [[ -z $latest_ooye_commit ]]; then
  latest_ooye_commit=$(awk 'NR == 1 {print $1}' <<<"$tag_refs")
fi

if [[ ! $latest_ooye =~ ^v[0-9] ]] || [[ ! $latest_ooye_commit =~ ^[0-9a-f]{40}$ ]]; then
  echo "Upstream returned an invalid OOYE release or commit." >&2
  exit 1
fi

if [[ $latest_ooye == "$OOYE_VERSION" && $latest_ooye_commit != "$OOYE_COMMIT" ]]; then
  echo "Upstream moved the existing $OOYE_VERSION tag; refusing an automatic commit change." >&2
  exit 1
fi
if [[ $latest_ooye != "$OOYE_VERSION" ]] && \
  [[ $(printf '%s\n%s\n' "$latest_ooye" "$OOYE_VERSION" | sort --version-sort | head -n 1) == "$latest_ooye" ]]; then
  echo "Upstream reports older OOYE release $latest_ooye; refusing an automatic downgrade." >&2
  exit 1
fi

node_sums=$(curl --proto '=https' --tlsv1.2 --fail --location --silent --show-error \
  https://nodejs.org/dist/latest-v22.x/SHASUMS256.txt)
node_line=$(awk '$2 ~ /^node-v22\.[0-9.]+-linux-x64\.tar\.xz$/ {print; exit}' <<<"$node_sums")
latest_node_sha=${node_line%% *}
latest_node_archive=${node_line##* }
latest_node=${latest_node_archive#node-}
latest_node=${latest_node%-linux-x64.tar.xz}

if [[ ! $latest_node =~ ^v22\.[0-9]+\.[0-9]+$ ]] || [[ ! $latest_node_sha =~ ^[0-9a-f]{64}$ ]]; then
  echo "Upstream returned an invalid Node.js release or checksum." >&2
  exit 1
fi

if [[ $latest_node == "$NODE_VERSION" && $latest_node_sha != "$NODE_LINUX_X64_SHA256" ]]; then
  echo "The checksum for existing Node.js $NODE_VERSION changed; refusing the update." >&2
  exit 1
fi
if [[ $latest_node != "$NODE_VERSION" ]] && \
  [[ $(printf '%s\n%s\n' "$latest_node" "$NODE_VERSION" | sort --version-sort | head -n 1) == "$latest_node" ]]; then
  echo "Upstream reports older Node.js release $latest_node; refusing an automatic downgrade." >&2
  exit 1
fi

sed -i \
  -e "s/^OOYE_VERSION=.*/OOYE_VERSION=$latest_ooye/" \
  -e "s/^OOYE_COMMIT=.*/OOYE_COMMIT=$latest_ooye_commit/" \
  -e "s/^NODE_VERSION=.*/NODE_VERSION=$latest_node/" \
  -e "s/^NODE_LINUX_X64_SHA256=.*/NODE_LINUX_X64_SHA256=$latest_node_sha/" \
  "$VERSIONS_FILE"

if [[ -n ${GITHUB_OUTPUT:-} ]]; then
  {
    echo "old_ooye=$OOYE_VERSION"
    echo "new_ooye=$latest_ooye"
    echo "new_ooye_commit=$latest_ooye_commit"
    echo "old_node=$NODE_VERSION"
    echo "new_node=$latest_node"
    echo "new_node_sha=$latest_node_sha"
  } >>"$GITHUB_OUTPUT"
fi

if [[ -n ${GITHUB_STEP_SUMMARY:-} ]]; then
  {
    echo "## Dependency update check"
    echo
    echo "- OOYE: \`$OOYE_VERSION\` → \`$latest_ooye\`"
    echo "- Node.js: \`$NODE_VERSION\` → \`$latest_node\`"
  } >>"$GITHUB_STEP_SUMMARY"
fi

printf 'OOYE: %s -> %s\nNode.js: %s -> %s\n' \
  "$OOYE_VERSION" "$latest_ooye" "$NODE_VERSION" "$latest_node"
