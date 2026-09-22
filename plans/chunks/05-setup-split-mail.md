# Chunk 05 — Setup Phase Split: Mail Stack

**Goal:** split the mail-service setup modules and relocate their durable state into the
persistent contract.

**Depends on:** 03
**Read first:** `../shared-context.md` + this file.
**Optional deep-dive (megaplan):** §Persistent Layout Contract; Current-Code Findings #3–#5.

## Scope

### `setup/mail-postfix.sh`

- Install phase: packages only. Configure phase: render Postfix config into the generation
  staging tree.
- Set `queue_directory` (and dependent spool paths) to `STATE_ROOT/postfix`; migrate existing
  queue contents on first container run of a migrated layout — never drop queued mail.
- chroot worker assumptions stay compatible with `SYS_CHROOT` capability.

### `setup/mail-dovecot.sh`

- Render Dovecot config to staging; auth socket/Postfix socket paths into `STATE_ROOT`;
  mail storage stays under `STORAGE_ROOT/mail`; Sieve config rendered, user sieve data
  persistent.
- `doveconf` validation of the staged generation before promotion.

### `setup/mail-users.sh`, `setup/dkim.sh`

- users.sqlite and mailboxes under `STORAGE_ROOT/mail`; OpenDKIM/OpenDMARC tables rendered
  to the generation, keys under `STORAGE_ROOT`; loopback milter ports unchanged
  (8891/8893, 10025/10026, 10023).

### `setup/spamassassin.sh`

- spampd/SpamAssassin config to generation; rule/runtime state to `STATE_ROOT/spamassassin`
  unless already covered by `STORAGE_ROOT`; Postgrey DB under `STORAGE_ROOT/mail`
  (per layout contract).

## Out of scope

- Supervisor program definitions (chunk 09); fail2ban rules (chunk 11).

## Verification

- [ ] `postfix check`, `doveconf` pass against staged generation.
- [ ] Queue persistence test: inject queued message, simulate pod replacement
      (state dir preserved), delivery resumes exactly once.
- [ ] Idempotent re-run; no writes outside `/home/miab` or `/run`/`/tmp` in container mode.
- [ ] Host-mode paths unchanged; contract tests pass.
