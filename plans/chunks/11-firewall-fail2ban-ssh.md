# Chunk 11 — Split Firewall, fail2ban & SSH Lockdown

**Goal:** implement the three-layer nftables model and the guarded optional SSH hardening
script.

**Depends on:** 02, 04 (verification uses the 02b harness)
**Read first:** `../shared-context.md` + this file.
**Optional deep-dive (megaplan):** §Networking/DNS/Firewall; §Administrative Access and Recovery;
§Firewall and security verification.

## Scope

### Host layer — `deploy/k3s/host/`

- `miab_host.nft` + installer: `inet miab_host` table, boot-persistent (systemd unit or
  nftables `include`), default-deny input, established/related, loopback, ICMP/ICMPv6,
  configured SSH port from any source, loopback/internal k3s+CNI+API traffic, MIAB public
  ports (TCP 25/80/443/465/587/993/995/4190, TCP+UDP 53). Atomic apply via `nft -c` +
  atomic ruleset swap; never flush non-owned tables.
- Host fail2ban package/config: `[sshd]` jail only, bans into `inet miab_ssh_bans`
  timeout sets; DB/log on host (node state).
- `lock-down-ssh` script: dry-run default; repeatable `--admin-cidr`; `--key-only`;
  verifies invoking admin's authorized key and `SSH_CONNECTION` source ∈ approved CIDRs;
  renders an sshd drop-in; `sshd -t` + `nft -c`; timed auto-rollback; requires second
  session + explicit `confirm`; `status`/`revert`; preserves prior files.

### Pod layer — container fail2ban config

- Split `[sshd]` out of `conf/fail2ban/jails.conf` (host owns it); pod jails for MIAB app
  services only, banning via `inet miab_dynamic` sets; DB under `STATE_ROOT/fail2ban`,
  logs under `STATE_ROOT/logs/fail2ban`; bans restored on pod start.
- Firewall helper `container/bin/miab-fw` constrained to `miab_dynamic` only — no arbitrary
  nft input, no default-policy changes.

## Verification

All checks run inside the `miab-test-host` podman harness — never on the development host
or a shared runner. The harness has its own netns, so nftables/fail2ban/sshd changes stay
contained. "Reboot" is approximated by container restart plus `boot-replay.sh` (real
boot-order verification defers to chunk 18).

- [ ] `nft -c` validation + atomic apply; container-restart + boot-replay test: baseline
      and SSH protection are active before k3s/pod start inside the harness.
- [ ] Host fail2ban bans/expiry on SSH only; pod fail2ban bans on app services only;
      neither touches the other's or k3s' tables.
- [ ] `lock-down-ssh`: unsafe input rejection, timed rollback, second-session confirm,
      CIDR allow/deny, key-only password rejection, idempotent reapply, full revert.
- [ ] IPv4-only and dual-stack render tests (empty IPv6 ⇒ no invalid rules).
