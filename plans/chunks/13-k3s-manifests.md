# Chunk 13 — k3s/Kustomize Deployment Assets

**Goal:** the complete, schema-valid Kubernetes tree for the MIAB workload on single-node k3s.

**Depends on:** 07, 09 (verification uses the 02b harness)
**Read first:** `../shared-context.md` + this file.
**Optional deep-dive (megaplan):** §Host and k3s Layer; §Workload Shape; §Kubernetes Resources and
Deployment Tooling; Impl. step 12.

## Scope

### `deploy/k3s/` Kustomize tree

- `namespace.yaml` — dedicated namespace + Pod Security labels required by
  `hostNetwork`/added capabilities (no cluster-wide weakening).
- `pv.yaml` / `pvc.yaml` — local PV on `/home/miab`, `Retain`, RWO, node affinity to
  `mailinabox.email/node=true`.
- `configmap.yaml` — non-secret inputs: PRIMARY_HOSTNAME, PUBLIC_IP, optional PUBLIC_IPV6,
  bind addresses, timezone, MTA-STS mode, resources, image digest.
- `deployment.yaml` — one replica, `strategy: Recreate`, `hostNetwork: true`,
  `dnsPolicy: None` + pod DNS 127.0.0.1, `automountServiceAccountToken: false`,
  `readOnlyRootFilesystem: true`, `emptyDir` for `/run` + `/tmp`, PVC at `/home/miab`,
  `capabilities.drop: [ALL]` + reviewed adds (CHOWN, DAC_OVERRIDE, FOWNER, SETGID, SETUID,
  KILL, NET_BIND_SERVICE, NET_ADMIN, SYS_CHROOT — minus any removed by audit),
  `privileged: false`, `hostPID/hostIPC: false`, runtime-default seccomp, startup/readiness/
  liveness probes, termination grace period, image digest placeholder.
- `secret.example.yaml` — bootstrap first-admin Secret template/instructions (no values).
- `jobs/` — `fresh-install`, `restore`, `validate` Job templates at the same digest with
  mode-specific commands and the same PVC mount.
- `kustomization.yaml` wiring it together; **no** Service/Ingress/LoadBalancer (host
  networking is the data path); no unused headless Service.

### k3s node scripts

- Pinned k3s install/config script: `--disable traefik --disable servicelb`, node label,
  API bound to loopback/internal only (no public 6443), root kubeconfig, prereq checks
  (amd64, cgroup v2, nftables, free ports, inotify limit).

## Verification

All checks inside the `miab-test-host` podman harness (nested k3s) — nothing installed or
changed on the development host.

- [ ] `kustomize build` renders; schema validation (kubeconform or `kubectl apply
      --dry-run=server`) against nested k3s of the pinned version.
- [ ] Manifest lint: no public Service/Ingress/LB, no SA token, no `privileged`,
      digest placeholder present.
- [ ] k3s install script is idempotent and refuses unsupported hosts — proven by running
      it inside the harness and against negative-fixture environments.
