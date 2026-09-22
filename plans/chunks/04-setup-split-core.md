# Chunk 04 — Setup Phase Split: system, ssl, dns

**Goal:** split the core host/OS-facing setup modules into install/configure phases and
redirect their MIAB-managed outputs to the persistent config/state contract.

**Depends on:** 03
**Read first:** `../shared-context.md` + this file.
**Optional deep-dive (megaplan):** §Persistent Layout Contract; §Build-Time vs Run-Time Separation;
§Networking, DNS, and Firewall.

## Scope

### `setup/system.sh`

- Move to install-phase-only: apt packages, hostname, swap, sysctl, journald,
  systemd-resolved, UFW, `systemctl` calls — all guarded so they never run in container
  runtime or configure phase.
- Keep configure-phase items that MIAB still owns: locale/timezone application to MIAB
  services, rsyslog/logrotate config renders (target `CONFIG_ROOT`), fail2ban config render
  (pod-side `miab_dynamic` only; SSH jail moves to host — see chunk 11).

### `setup/ssl.sh`

- Install phase: packages only.
- Configure phase: TLS material, DH params consumption (built at image time in container
  mode — see chunk 07), ACME account state under `STORAGE_ROOT/ssl`, certificate provisioning
  stays runtime-triggered; self-signed fallback generation idempotent.
- Never regenerate existing keys/certs on re-run.

### `setup/dns.sh`

- Configure phase writes rendered bind9/NSD config to the generation tree
  (`CONFIG_ROOT` staging), zone files/serials to `STATE_ROOT/nsd/zones`, DNSSEC keys under
  `STORAGE_ROOT/dns/dnssec`.
- Remove any resolver/hostname mutation in container mode.

## Out of scope

- The generation staging/promotion machinery itself (chunk 08) — write to the staging dir
  via the helpers from chunks 02/03.
- nftables/firewall rules (chunk 11).

## Verification

- [ ] Rendered config lands under the staging generation path, not `/etc`, in container mode.
- [ ] `named-checkconf`, `nsd-checkconf` pass on rendered output (IPv4-only and dual-stack).
- [ ] Idempotent second run: no key/cert/zone regeneration, no diffs.
- [ ] Host mode: `setup/start.sh` output paths unchanged; contract tests pass.
