## Summary

Describe the host deployment change and why it is needed.

## Validation

- [ ] `./scripts/validate.sh`
- [ ] Upstream OOYE and Node.js release notes reviewed when changing pins
- [ ] No `registration.yaml`, database, Discord credential, or appservice token included

## Operations

- [ ] A stopped-service OOYE backup exists before an upgrade
- [ ] Required VPS, systemd, firewall, or Coolify proxy changes are documented
