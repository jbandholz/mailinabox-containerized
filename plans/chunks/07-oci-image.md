# Chunk 07 — OCI Image Build

**Goal:** reproducible, pinned, registry-neutral `linux/amd64` Ubuntu 22.04 image containing
all install-phase artifacts and no instance state.

**Depends on:** 04, 05, 06 (install-phase classification must exist)
**Read first:** `../shared-context.md` + this file.
**Optional deep-dive (megaplan):** §Build-Time vs Run-Time Separation; §Capability and Security Model;
§CI, Image Publication; Impl. step 4.

## Scope

### Files to create

- `container/Dockerfile` — multi-stage build; base `ubuntu:22.04` pinned by digest;
  runs the `install` phase of `setup/reconcile.sh`; final stage excludes build tools where
  practical; `DEBIAN_FRONTEND=noninteractive`; apt caches cleared.
- `container/.dockerignore` — exclude repo state, secrets, tests, `.git`.
- `container/packages.lock` — recorded apt package versions + snapshot date.
- `container/assets.lock` — Roundcube/plugins, Nextcloud (current + one-back migration
  assets, i.e. 26→27), Z-Push, management assets: pinned revisions + sha256.
- `container/requirements*.txt` / constraints — locked Python deps with hashes for the
  management virtualenv.
- `container/bin/` — entrypoint dispatch, layout init, probes, `miab-service`, firewall and
  validation helpers (implemented in chunks 08/09; create skeletons + entry dispatch now).
- Image labels: MIAB version, source commit, build date, compatibility/layout version —
  the fields `miab-update` later cross-checks against the release manifest.

## Behavior requirements

- Image build performs **only** install-phase work; zero instance state, hostnames, keys,
  or secrets in any layer.
- Capture pristine package/vendor config into `/usr/share/mailinabox/config-defaults`
  with checksums (generation seeding input for chunk 08).
- Bake fixed symlinks/launchers pointing MIAB-managed legacy paths to
  `/home/miab/config/current` (populated by chunk 09 as each daemon is wired).
- Pre-generate public/non-instance DH params at build time.
- Deterministic service users/groups with fixed numeric UIDs/GIDs matching the
  `/home/miab` ownership contract.

## Verification

- [ ] Build twice from locked inputs; diff package/asset/SBOM lists (document apt variance).
- [ ] Image scan: no private keys, credentials, instance identity, or package caches.
- [ ] `docker image inspect` labels complete and match `assets.lock`/`packages.lock`.
- [ ] Image runs `--version`/metadata dump command without starting services.
