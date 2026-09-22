# Chunk 02b — Synthetic Test Harness (`miab-test-host` podman image)

**Goal:** a self-contained podman image that simulates the Ubuntu host for all synthetic
verification — zero changes to the development host system.

**Depends on:** none — the harness itself needs no fixtures. Build it early/in parallel;
**Read first:** `../shared-context.md` + this file.
it is required by chunk 01's golden capture and by all verification in 09, 11, 13–16.
**Optional deep-dive (megaplan):** §Confirmed Decisions "Testing tiers"; §Verification intro.

## Hard constraint

**No changes to the development host.** No host package installs, no host firewall/
fail2ban/sshd/k3s changes, no `/home/miab` on the host, no host bind-mounts other than an
optional scratch volume. Everything runs inside podman containers with their own
network/mount namespaces.

## Scope

### `tests/container/harness/`

- `Containerfile` — `miab-test-host` image: Ubuntu 22.04 + systemd (PID 1), openssh-server,
  fail2ban, nftables, k3s binary, podman or nested-containerd support, kubectl, test
  tooling (python3, pytest, bats, openssl, swaks/dnsutils stubs).
- `run-harness.sh` — `podman run` wrapper: own netns (never `--network=host`), scratch
  volume for `/home/miab` inside the container, cap/cgroup settings needed for nested
  k3s+containerd (documented; sandbox may be privileged — that privilege is test infra
  only and never applies to the MIAB workload image).
- `sim-peers/` — stub services for external dependencies: fake DNS resolver/root hints,
  stub ACME endpoint, sink/source SMTP peer, fake update-source registry/file tree.
- `boot-replay.sh` — approximates host boot inside the container: ordered service start
  (nftables persistence → sshd → fail2ban → k3s) plus container restart; used in place of
  a true kernel reboot. Real boot-order verification is deferred to chunk 18.
- `Makefile`/scripts to build the harness, run a named test scenario, and collect artifacts.

### Operating modes the harness must support

1. **k3s-in-podman:** nested k3s+containerd running the MIAB Deployment/Jobs — for
   install/update/restore/lifecycle tests.
2. **Direct `podman run` of the MIAB image** inside or beside the harness — for app-level
   and config-generation tests that don't need Kubernetes.
3. **Host-simulation:** sshd/fail2ban/nftables "host" components and `miab-*` host commands
   execute inside the harness as if it were the node.

## Verification

- [ ] `podman build` + `run-harness.sh` produces a working simulated host with sshd,
      nftables, fail2ban, and nested k3s answering `kubectl get nodes`.
- [ ] Prove zero host mutation: run harness, then diff host package list, nft ruleset,
      listening sockets, and `/home` contents before/after — identical.
- [ ] `boot-replay.sh` reproduces boot ordering inside a fresh container start.
- [ ] Harness is disposable: `podman rm` leaves nothing behind except the scratch volume
      (which is also removable).
