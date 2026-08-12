# Native OOYE bridge for Continuwuity

This repository provisions [Out Of Your Element (OOYE)](https://gitdab.com/cadence/out-of-your-element), a Matrix–Discord bridge, as a native systemd service on the Debian 13 VPS that hosts Coolify. It does not containerize OOYE and does not deploy automatically from GitHub.

The deployment pins both upstream OOYE and Node.js, installs OOYE under an unprivileged account, and uses Coolify's existing Traefik proxy for the required public HTTPS bridge website.

## Architecture

```text
Discord ↔ OOYE (/opt/ooye, systemd)
                │
                ├── https://matrix.example.org → Coolify → Continuwuity
                └── :6693 on the Debian host
                         ↑
Internet → https://bridge.example.org → Coolify Traefik
                         ↑
Continuwuity → host.docker.internal:6693
```

OOYE's website must be publicly reachable over HTTPS for authenticated-media proxying and bridge administration. Raw port 6693 must not be publicly reachable; only Coolify's Traefik and Docker-host traffic should reach it.

## What is pinned

[`config/versions.env`](config/versions.env) is the single source of truth for:

- The stable OOYE release and exact upstream commit
- The Node.js 22 release and SHA-256 checksum for the official x86-64 archive

Debian 13's own Node.js package is version 20, while OOYE requires Node.js 22 or newer. The installer therefore downloads the pinned official Node.js archive, verifies its checked-in checksum, installs it under `/opt`, and points `/opt/node` at that version.

## Prerequisites

- Debian 13 x86-64 with Coolify v4 and its default Traefik proxy
- Root SSH access through `root@debian`
- DNS for the permanent Matrix hostname, such as `matrix.example.org`
- DNS for a public OOYE hostname, such as `bridge.example.org`
- A Discord application and bot
- An initialized Continuwuity administrator account
- Provider and host firewall rules allowing public SSH, 80, and 443, but not 6693

Do not run OOYE itself as root. The installer uses root only to provision packages, files, the `ooye` account, and systemd.

## Install the host prerequisites

Clone this deployment repository on the VPS and run its installer:

```bash
ssh root@debian
git clone https://github.com/declarative-dale/matrix-discord-bridge.git \
  /opt/matrix-discord-bridge-deploy
cd /opt/matrix-discord-bridge-deploy
./scripts/install.sh
```

The installer:

- Installs build prerequisites from Debian
- Creates the locked-down `ooye` system account
- Downloads and verifies pinned Node.js
- Checks out the pinned OOYE tag and commit at `/opt/ooye`
- Installs production npm dependencies
- Enables the temporary Sharp decoder workaround when the installed Sharp is older than `0.35.0`
- Installs `/etc/systemd/system/ooye.service`

It deliberately does not run interactive setup, enable the service, edit Coolify, or handle secrets.

## Route the public bridge hostname through Coolify

Before running OOYE setup, add a server-level Traefik dynamic configuration in **Coolify → Server → Proxy → Dynamic Configurations**. Start with [`coolify/ooye.yaml`](coolify/ooye.yaml).

Replace `bridge.example.org`. Also confirm the Docker host gateway address rather than blindly assuming `172.17.0.1`:

```bash
docker inspect coolify-proxy \
  --format '{{range $name, $network := .NetworkSettings.Networks}}{{println $name $network.Gateway}}{{end}}'
```

Choose an address reachable from `coolify-proxy`, set it in the dynamic configuration's backend URL, and configure DNS for the bridge hostname. Coolify will obtain the HTTPS certificate. The proxy configuration sends both the public website and health checks to native OOYE on port 6693.

Ensure the host or provider firewall does not permit public inbound TCP/6693. If a host firewall is enabled, it must still allow the relevant Docker bridge subnet to reach TCP/6693. Docker networking and firewall rules vary, so verify the actual interfaces and subnets on the VPS rather than copying a generic rule.

## Run interactive OOYE setup

Start setup as the unprivileged account:

```bash
runuser -u ooye -- env \
  HOME=/opt/ooye \
  PATH=/opt/node/bin:/usr/bin:/bin \
  /opt/node/bin/npm --prefix /opt/ooye run setup
```

Use these answers where requested:

```text
Matrix server name: matrix.example.org
Homeserver URL: https://matrix.example.org
OOYE web server port: 6693
Public OOYE URL: https://bridge.example.org
```

Setup will also securely prompt for the Discord bot token and application details. It temporarily starts OOYE on port 6693 and verifies that the public URL reaches it through Traefik.

When setup says that `registration.yaml` has been generated and waits for homeserver registration, leave it running and open a second SSH session. Change only the top-level application-service callback URL:

```bash
cd /opt/matrix-discord-bridge-deploy
./scripts/set-appservice-url.sh
```

This produces the intended split:

```text
registration.url = http://host.docker.internal:6693
registration.ooye.bridge_origin = https://bridge.example.org
```

The first is the private callback Continuwuity uses from its container. The second remains OOYE's public HTTPS website and media-proxy origin.

In the Continuwuity admin room, send the complete contents of `/opt/ooye/registration.yaml` in a fenced code block below:

````text
!admin appservices register
```
<complete registration.yaml contents>
```
````

Then verify:

```text
!admin appservices list
```

Allow setup to finish. Never paste registration data into GitHub, CI logs, tickets, or chat outside the private admin room.

## Start OOYE

```bash
systemctl enable --now ooye.service
systemctl status ooye.service
journalctl -u ooye.service -f
```

Verify all of the following:

```bash
curl --fail http://127.0.0.1:6693/
curl --fail https://bridge.example.org/
```

- The public URL has a valid HTTPS certificate.
- Port 6693 is unreachable from an external machine.
- Continuwuity lists `ooye` as a registered appservice.
- A test message bridges from Discord to Matrix and from Matrix to Discord.
- Rebooting the VPS brings back both Coolify/Continuwuity and `ooye.service`.

## Secrets and persistent state

OOYE stores its generated configuration and SQLite database in its working directory:

```text
/opt/ooye/registration.yaml
/opt/ooye/ooye.db*
```

These contain Discord credentials, application-service tokens, and bridge state. They must never be committed. The deployment repository ignores their names, and CI rejects them if they are force-added.

Back up OOYE with the supplied stopped-service procedure:

```bash
cd /opt/matrix-discord-bridge-deploy
./scripts/backup.sh
```

Backups default to root-only archives in `/var/backups/ooye`. The script stops OOYE before reading SQLite files and restarts it if it was previously active. Copy encrypted backups off the VPS and periodically test restoration. Continuwuity's named volume requires its own separate, application-consistent backup.

## Updating

Every Monday, GitHub Actions checks the official latest stable OOYE release and the latest Node.js 22 archive. When either pin changes, it updates `config/versions.env` on `automation/dependency-updates`, downloads and verifies the proposed Node.js archive, installs the pinned OOYE production dependencies in a temporary checkout, validates the repository, and opens or refreshes a pull request. It never connects to the VPS or deploys the update.

Enable **Settings → Actions → General → Workflow permissions → Allow GitHub Actions to create and approve pull requests** so the workflow may create the PR. The workflow does not approve its own PR.

After reviewing and merging an update:

```bash
ssh root@debian
cd /opt/matrix-discord-bridge-deploy
git pull --ff-only
./scripts/update.sh
systemctl status ooye.service
```

The update script refuses tracked upstream modifications, installs the newly pinned Node version, makes a stopped-service backup, checks out the exact pinned OOYE commit, reinstalls production dependencies, and restores the prior running state. Review upstream release notes before approval and test Matrix↔Discord traffic afterwards.

## GitHub automation

- `validate.yml` checks shell syntax, ShellCheck findings, the version-pin format, systemd unit validity, proxy YAML, and secret/state boundaries.
- `update-dependencies.yml` proposes weekly OOYE and Node.js updates as reviewable PRs.
- `dependency-review.yml` flags vulnerable or disallowed dependency changes in pull requests.
- `security-audit.yml` audits the pinned upstream OOYE production lockfile every Wednesday without executing dependency install scripts.
- Dependabot proposes updates for the GitHub Actions themselves.

GitHub Actions has read-only permissions except for the scheduled update workflow, whose write access is limited to repository contents and pull requests. No VPS SSH key, Discord token, Matrix token, registration file, or Coolify credential belongs in GitHub.

### Current upstream security finding

As of 2026-08-12, OOYE `v3.6` resolves `sharp` below `0.35.0`. npm reports [GHSA-f88m-g3jw-g9cj](https://github.com/advisories/GHSA-f88m-g3jw-g9cj), a high-severity advisory covering inherited libvips vulnerabilities. npm only offers a semver-major `sharp` update, so this repository does not force an unsupported dependency override into the upstream application.

While the installed Sharp version is below `0.35.0`, [`sharp-workaround.cjs`](security/sharp-workaround.cjs) is preloaded through systemd and applies the advisory's workaround:

```javascript
sharp.block({ operation: ["VipsForeignLoadNsgif", "VipsForeignLoadTiff", "VipsForeignLoadVips"] });
```

This prevents OOYE from decoding GIF, TIFF, and VIPS images. PNG and other unblocked formats continue to work. The installer and updater inspect `/opt/ooye/node_modules/sharp/package.json`; when upstream OOYE resolves Sharp `0.35.0` or newer, they delete `/etc/ooye-security.env` and the installed preload automatically before restarting OOYE. No manual cleanup or upstream source modification is required.

The scheduled security audit will remain red until a pinned stable OOYE release resolves the advisory. Review the affected image-processing paths and upstream remediation before production deployment. When a fixed stable OOYE release is published, the Monday update workflow will propose it for review.

## Recovery notes

To restore OOYE, stop `ooye.service`, preserve the failed state for diagnosis, restore `registration.yaml` and all matching `ooye.db*` files from the same stopped-service archive into `/opt/ooye`, restore ownership to `ooye:ooye` and mode `0600`, then start the service. Do not combine a database from one backup with registration data from another.

If you regenerate the application-service registration, unregister or replace the old registration in Continuwuity and ensure its top-level `url` is reset to `http://host.docker.internal:6693` before registering it.
