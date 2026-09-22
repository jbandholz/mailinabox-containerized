# Chunk 15 — `miab-update` Host Transaction & Release Manifest

**Goal:** the immutable update lifecycle for MIAB code + OS/packages: trusted discovery,
compatibility planning, offline reconciliation, digest rollout, schema-aware rollback.

**Depends on:** 08, 13, 14
**Read first:** `../shared-context.md` + this file.
**Optional deep-dive (megaplan):** §MIAB Code and Image Update Mechanism; Impl. step 10; Acceptance #8.

## Scope

### `container/release-manifest.schema.json` + `deploy/k3s/`

Manifest fields: schema version, minimum updater version, MIAB version, container release,
source commit, exact image digest, arch, build timestamp, supported source/layout versions,
target layout, migration id, reconciliation-contract version/hash, `rollback_class`
(`image-only`|`restore-required`), release-notes/security flag, SBOM/provenance refs.
Trust policy: pinned public key or keyless identity/issuer; reject unsigned/mutable-tag/
arch/digest-mismatch metadata.

### `deploy/k3s/bin/miab-update` — `check|plan|apply|status|rollback`, `--image <digest>`

- `check`: fetch+verify metadata; compare versions/digests; verify own schema compat;
  write non-secret `STATE_ROOT/update/status.json`. Optional systemd timer = check only.
- `plan`: capacity, version/layout compat, registry reachability, signature/provenance,
  workload health, pending ops, rollback needs; prints downtime/rollback; zero mutation.
- `apply` (locked, durable receipt):
  1. resolve manifest→digest, pull/import before downtime;
  2. new image's non-mutating validation Job;
  3. fresh verified pre-update backup;
  4. quiesce + scale serving Deployment to 0;
  5. `offline-upgrade` Job at new digest under `instance.lock` — complete configure
     reconciliation incl. migrations, Nextcloud/Roundcube, permissions, validation;
  6. apply Deployment at exact digest; `startup` validates promoted generation read-only;
  7. postflight: DNS, TLS, SMTP, IMAP, API, DB integrity, Nextcloud/Roundcube, queue,
     layout;
  8. atomic receipt/history.
- Phase-aware failure handling per megaplan: candidate-config fail ⇒ `current` untouched;
  pre-mutation ⇒ restart old digest; backward-compat ⇒ prior generation + authorized image
  rollback; non-backward-compat ⇒ verified backup restore + old digest.
- `rollback`: executes the manifest-authorized path; refuses digest-only rollback when
  `rollback_class=restore-required`.
- Node tooling too old ⇒ fail closed; separate signed atomic node-tooling upgrade with
  retained rollback copy. Pod never gets registry creds or k8s RBAC.

## Verification

Synthetic only, inside the `miab-test-host` podman harness: nested k3s, local OCI layout
or `podman save` tarballs standing in for the registry, self-signed test manifests/keys
for the trust policy. No development-host changes. Real channel/registry validation
defers to chunk 18.

- [ ] Reject tampered/unsigned/unsupported manifests, wrong arch, digest mismatch,
      unmet min-updater, concurrent ops, missing backup — all before mutation.
- [ ] `image-only` update: pulled pre-downtime, exact digest, queue survives, receipts
      record source/target commits.
- [ ] Migration update: full reconcile parity with conventional `setup/start.sh` rerun.
- [ ] All failure-injection rollback paths proven (per megaplan checklist).
- [ ] Local `--image <digest>` path works registry-free with identical gates.
