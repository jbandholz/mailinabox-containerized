# Chunk 06 — Setup Phase Split: Web, Apps, migrate, firstuser

**Goal:** split the web/groupware/management/monitoring setup modules and the migration entry
points.

**Depends on:** 03
**Read first:** `../shared-context.md` + this file.
**Optional deep-dive (megaplan):** §Persistent Layout Contract; Findings #8–#9; §Migration restore Job.

## Scope

### `setup/web.sh`, `setup/webmail.sh`, `setup/zpush.sh`

- Install phase: packages/asset fetch only (assets pinned in image, chunk 07).
- Configure phase: nginx/PHP-FPM/Roundcube/Z-Push config into generation staging;
  Roundcube DB + temp/log paths per layout (`STORAGE_ROOT/mail` DB, `STATE_ROOT/logs`);
  Z-Push state to `STATE_ROOT/z-push`.
- Roundcube `updatedb` runs in configure phase only (offline-upgrade path), idempotently.

### `setup/nextcloud.sh`

- Configure phase: Nextcloud config/data under `STORAGE_ROOT/owncloud`; `occ` upgrade and
  `occ` maintenance commands in configure phase with services quiesced; uses image-bundled
  assets for v26→v27 step — no downloads.
- `owncloud-backup` snapshot semantics preserved.

### `setup/management.sh`, `setup/munin.sh`

- Management daemon config (gunicorn/supervisor handoff) and API key path
  `STATE_ROOT/mailinabox/api.key`; status cache `STATE_ROOT/mailinabox/status-cache`.
- Munin DB/HTML/node state to `STATE_ROOT/munin/{db,html,node}`; rendered configs to
  generation; logs to `STATE_ROOT/logs/munin`.

### `setup/migrate.py`, `setup/firstuser.sh`

- `migrate.py`: layout-aware preconditions, per-migration receipts under
  `STATE_ROOT/update/receipts` (container) while preserving numbering for host.
- `firstuser.sh`: skipped by `fresh-install` Job (no management daemon); runs post-deploy
  via live API/CLI per megaplan §6A.

## Verification

- [ ] `nginx -t`, PHP-FPM config test pass on staged generation.
- [ ] Nextcloud/Roundcube upgrade path runs fully offline against v75 fixtures.
- [ ] No downloads or daemon actions in configure phase; idempotent re-run.
- [ ] Host-mode parity: contract tests unchanged.
