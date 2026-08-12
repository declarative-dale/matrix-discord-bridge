#!/usr/bin/env bash
set -euo pipefail

REGISTRATION_FILE=${1:-/opt/ooye/registration.yaml}
APPSERVICE_URL=${2:-http://host.docker.internal:6693}

if [[ ${EUID} -ne 0 ]]; then
  echo "Run this script as root." >&2
  exit 1
fi

if [[ ! -f $REGISTRATION_FILE ]]; then
  echo "Registration file not found: $REGISTRATION_FILE" >&2
  exit 1
fi

runuser -u ooye -- /opt/node/bin/node - "$REGISTRATION_FILE" "$APPSERVICE_URL" <<'NODE'
const fs = require("node:fs")
const [file, appserviceUrl] = process.argv.slice(2)
const registration = JSON.parse(fs.readFileSync(file, "utf8"))
registration.url = appserviceUrl
const temporary = `${file}.tmp`
fs.writeFileSync(temporary, `${JSON.stringify(registration, null, 2)}\n`, {mode: 0o600})
fs.renameSync(temporary, file)
NODE

chmod 0600 "$REGISTRATION_FILE"
echo "Set the application-service callback to $APPSERVICE_URL."
echo "The public ooye.bridge_origin value was left unchanged."
