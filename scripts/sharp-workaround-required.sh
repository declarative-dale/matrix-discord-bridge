#!/usr/bin/env bash
set -euo pipefail

SHARP_VERSION=${1:?Pass the installed Sharp version}
FIXED_VERSION=0.35.0

if [[ ! $SHARP_VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Invalid Sharp version: $SHARP_VERSION" >&2
  exit 2
fi

lowest_version=$(printf '%s\n%s\n' "$SHARP_VERSION" "$FIXED_VERSION" | sort --version-sort | head -n 1)
[[ $SHARP_VERSION != "$FIXED_VERSION" && $lowest_version == "$SHARP_VERSION" ]]
