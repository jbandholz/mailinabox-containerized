# Chunk 01 — Contract Tests & Fixtures

**Goal:** capture current MIAB behavior as executable contracts before any refactoring, so later
chunks can prove parity.

**Depends on:** static contracts — none; golden capture — 02b (runs inside `miab-test-host`).
**Read first:** `../shared-context.md` + this file.
**Optional deep-dive (megaplan):** §Implementation Steps step 1; §Verification.

## How capture runs

Two layers — only the second needs a running system, and it runs **inside the podman
harness**, never on the development host.

### Layer A — static contracts (no execution, run anywhere)

Parse the source to generate the inventory — these tests run on the unmodified tree and on
every later change:

- Daemon/port inventory extracted from `setup/*.sh`, `conf/*`, `management/daemon.py`
  routes, `conf/fail2ban/jails.conf` — public TCP 25/80/443/465/587/993/995/4190,
  TCP+UDP 53; loopback 953/10023/10025/10026/8891/8893/10222.
- Ordered module list parsed from `setup/start.sh` — the parity fixture for chunk 03.
- Management API route table parsed from `management/daemon.py` decorators.

### Layer B — golden capture (inside `miab-test-host`, chunk 02b)

A scenario script `tests/container/harness/capture-golden.sh`:

1. `podman run` the harness image (systemd as PID 1, own netns, scratch volume for
   `/out`), bind-mounting the repo read-only plus `tests/container/fixtures/` writable —
   writing fixture files into the worktree is a workspace output, not a host-system change.
2. Run the real installer noninteractively inside the container:

   ```bash
   env NONINTERACTIVE=1 SKIP_NETWORK_CHECKS=1 \
       PRIMARY_HOSTNAME=box.test PUBLIC_IP=<harness-ip> PUBLIC_IPV6= \
       EMAIL_ADDR=admin@box.test EMAIL_PW=<disposable-test-only> \
       bash setup/start.sh
   ```

   `SKIP_NETWORK_CHECKS` bypasses `setup/network-checks.sh` (Spamhaus/PTR checks need real
   public DNS — not available and not needed for schema capture). The password is a
   throwaway in-container value, never committed.
3. After setup completes, snapshot into `/out/golden-v76/`:
   - `find $STORAGE_ROOT` file tree + `sqlite3 .schema` dumps (users, Roundcube, Nextcloud);
   - generated `/etc` file list + normalized sha256 manifest;
   - `systemctl list-units --type=service --state=running`, `ss -tlnup` listener table,
     `fail2ban-client status` jail list;
   - management API responses via `curl --key`/api.key on `127.0.0.1:10222`;
   - `dpkg -l` package manifest, `mailinabox.version`, `/etc/mailinabox.conf` (normalized).
4. `normalize.py` scrubs hostnames, IPs, keys, timestamps, salts → committed fixtures.

The same capture script later produces the **v75 fixture** by running the tagged v75
source in the harness (plus a v75 backup archive for chunk 16).

## Scope

### Files to create

- `tests/container/conftest.py` — fixture helpers (temp STORAGE_ROOT, fake service runner, env overrides).
- `tests/container/test_service_inventory.py` — asserts the parsed daemon/port inventory.
- `tests/container/test_storage_schema.py` — compares golden STORAGE_ROOT schema fixture.
- `tests/container/test_setup_order.py` — ordered module list from `setup/start.sh`.
- `tests/container/test_management_api_contract.py` — golden API responses; intentional
  changes (apt/reboot/UFW/SSH checks) become explicit diffs in later chunks.
- `tests/container/harness/capture-golden.sh`, `normalize.py` — the capture pipeline.
- `tests/container/fixtures/golden-v76/`, `golden-v75/` — normalized captures.

### Files to modify

- `pyproject.toml` / test config only if needed to include `tests/container/`.

## Verification

- [ ] `pytest tests/container/` passes on the unmodified tree using golden fixtures.
- [ ] Golden capture runs end-to-end in the harness; host system untouched.
- [ ] Fixtures are normalized (no real keys/passwords/hostnames committed).
- [ ] Fixture docs record which behaviors may intentionally change later.
