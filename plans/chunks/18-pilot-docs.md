# Chunk 18 — Production-Pilot Qualification & Documentation

**Goal:** prove the milestone on real infrastructure and update all operator-facing docs.

**Depends on:** all prior chunks
**Read first:** `../shared-context.md` + this file.
**Optional deep-dive (megaplan):** §Verification (all); §Acceptance Criteria; Impl. steps 14–15.

This is the **only** chunk that requires real public infrastructure — every earlier chunk
verifies synthetically inside podman. The pilot runs on a **separate disposable public
node**, never on the development host. Do not start until all prior chunks' synthetic
gates pass.

## Scope

### Pilot execution — disposable public Ubuntu node

Requires correct forward/reverse DNS and unblocked outbound TCP/25.

- Fresh `miab-install` end-to-end; interrupted-install recovery.
- v76 restore; v75 restore with offline migration.
- `miab-update` image-only and migration updates; every rollback class.
- Node reboot; pod recreation; queued-mail durability (exact message, exactly once).
- Public protocol matrix: DNS TCP/UDP + DNSSEC, SMTP 25/465/587, IMAP 993, POP 995,
  Sieve 4190, HTTP→HTTPS, admin UI, Roundcube, Nextcloud DAV, Z-Push, Munin, API, cron.
- Firewall: baseline survives reboot independent of pod; host vs pod fail2ban separation;
  `lock-down-ssh` full cycle + revert; no k3s-table interference.
- Certificate cycle/dry-run, DNSSEC re-sign, nightly backup/status, Nextcloud cron,
  log rotation, delivery retry.
- State-escape test on the real deployment (read-only root + snapshot diff).
- Record: host OS, k3s version, image digest, SBOM/provenance, manifest digest, results,
  warnings, rollback point → release sign-off.

### Documentation

- `README.md`: container deployment prerequisites, `miab-install`, first user, update
  channels, restore, rollback, firewall recovery, limitations, decomposition contract.
- `security.md`: capability/firewall/SSH/update-trust model.
- `--help` text for all new commands; `management/templates/system-status.html` wording;
  API schema/docs where behavior changed.
- Do **not** touch `CONTRIBUTING.md` (user-owned changes).

## Verification

- [ ] Every megaplan §Verification checkbox executed or explicitly waived with reason.
- [ ] All 12 Acceptance Criteria demonstrated on the pilot node.
- [ ] Sign-off record committed alongside release manifest.
