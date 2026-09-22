# Chunk 14 — `miab-install` Host Transaction

**Goal:** root-only host command implementing the resumable initial-install transaction.

**Depends on:** 08, 13 (verification uses the 02b harness)
**Read first:** `../shared-context.md` + this file.
**Optional deep-dive (megaplan):** §Initial Installation Transaction; Impl. step 9; Acceptance #1.

## Scope

### `deploy/k3s/bin/miab-install`

Subcommands: `preflight`, `apply`, `status`, `recover`. TTY prompts + noninteractive
flags/config; never logs/persists admin plaintext passwords.

- `preflight`: amd64, Ubuntu 22.04+, hostname/public IPv4 (+opt IPv6), forward/reverse DNS,
  outbound TCP/25, required free ports, host SSH continuity, k3s/CNI/API health, nftables
  baseline + host fail2ban present, disk/RAM, `/home/miab` emptiness/layout state, image
  signature/digest/embedded metadata.
- `apply` transaction:
  1. host install/update/restore lock; refuse unknown non-empty layout unless recovery;
  2. resolve/pull or locally import exact trusted digest before touching state;
  3. create namespace, node label, Retain PV/PVC, ConfigMap, short-lived bootstrap Secret
     only if noninteractive admin creds supplied;
  4. run one-shot `fresh-install` Job (same digest, no SA token) — full configure pipeline,
     receipt written last;
  5. apply serving Deployment at same digest; require read-only startup validation +
     readiness;
  6. create first admin via live management API/CLI (secure prompt or bootstrap Secret),
     required aliases, trigger `live-reconfigure` for DNS/web;
  7. delete bootstrap Secret; run protocol postflight; atomically mark install complete.
- `status`: reports current module/receipt state of an in-progress or failed install.
- `recover`: explicit `resume` (idempotent module replay) or guarded `reinitialize`
  (requires confirmation; never silently deletes generated keys/state).

## Failure semantics

- Any pre-completion failure leaves a non-serving, inspectable layout; the serving
  Deployment is never created until the install receipt exists.
- Partial state is preserved for forensics/resume.

## Verification

Runs entirely inside the `miab-test-host` podman harness: nested k3s, fixture image
imported into the nested containerd, stubbed external DNS (preflight must accept
injectable check results). No development-host changes. Public-DNS/CA validation is
deferred to chunk 18.

- [ ] Preflight rejects each invalid condition without mutating `/home/miab`.
- [ ] Happy path on empty `/home/miab` reaches Ready end-to-end inside the harness.
- [ ] Failure injection at multiple modules → correct status, idempotent resume, guarded
      reinitialize, no silent data loss.
- [ ] No plaintext password in history/logs/manifests/receipts; bootstrap Secret removed.
