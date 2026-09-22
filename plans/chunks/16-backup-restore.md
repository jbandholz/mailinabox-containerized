# Chunk 16 — Backup Expansion & Restore/Migration Job

**Goal:** extend backups to the full `/home/miab` state contract and implement the offline
restore Job supporting same-release and one-back migration.

**Depends on:** 10, 13
**Read first:** `../shared-context.md` + this file.
**Optional deep-dive (megaplan):** §Backups and Restore/Migration; Impl. step 11; Acceptance #7.

## Scope

### Ongoing backups — `management/backup.py`, `management/daily_tasks.sh`

- Source contract: versioned `/home/miab` set (config inputs/secrets, active + bounded
  prior generations, receipts, data, state) — excluding backup destination/cache, restore
  staging, and ephemeral locks.
- Quiesce all writers via `service_ctl` under a maintenance lock; back up; restart in
  dependency order; re-run readiness.
- Keep file/rsync/S3/B2 targets; move backup SSH identity `/root/.ssh/id_rsa_miab` →
  `STATE_ROOT/backup-ssh`.
- Backup metadata: MIAB release, image revision, layout version, arch, timestamp,
  integrity hashes.

### Restore — `container/bin/miab-restore` + `deploy/k3s/jobs/restore.yaml`

- Requires serving Deployment scaled to 0; takes `instance.lock` non-blocking.
- Accepts duplicity sources + separately supplied credentials (never in image/YAML).
- Stage into `/home/miab/restore/staging` — never over live data.
- Validation: release == image release or exactly one back; `mailinabox.version`, SQLite
  DBs, mailboxes, SSL/DNSSEC/DKIM, Nextcloud config present; `integrity_check` passes;
  archive paths/symlinks confined to staging (no absolute paths, traversal, devices);
  disk space + arch/layout checks.
- Legacy host backups → promote into `/home/miab/data`, init missing state subtrees,
  normalize ownership, run full `offline-upgrade` reconciliation (image assets only).
- Container-layout backups → restore complete versioned contract.
- Atomic promote only after all checks; restore receipt (source/target release, hashes,
  timestamp, migrations); then Deployment start + post-restore checks.
- Refuse older backups with upgrade-first instructions.

## Verification

Synthetic only, inside the `miab-test-host` podman harness: nested k3s, local
filesystem/rsync targets (S3/B2 via stub or documented skip), chunk-01 backup fixtures.
No development-host changes. Real remote-target and public-protocol validation defers to
chunk 18.

- [ ] Backups complete/verify per target class; metadata present; quiesce ordering proven.
- [ ] v76 fixture restore → services ready, protocol checks pass.
- [ ] v75 fixture restore → offline v75→v76 MIAB/Nextcloud/Roundcube migration → same checks.
- [ ] Malicious/corrupt archives (traversal, escaping symlink, truncated DB, wrong version,
      active lock) each fail before promotion.
