#!/bin/bash
set -euo pipefail

fail() {
	printf 'sync-upstream: %s\n' "$1" >&2
	exit 1
}

repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || fail "run this command from inside the repository"
cd "$repo_root"

starting_branch=$(git symbolic-ref --quiet --short HEAD) || fail "detached HEAD is not supported"

restore_branch() {
	current_branch=$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)
	if [ "$current_branch" != "$starting_branch" ]; then
		git switch --quiet "$starting_branch" || printf 'sync-upstream: could not restore branch %s\n' "$starting_branch" >&2
	fi
}
trap restore_branch EXIT

[ -z "$(git status --porcelain --untracked-files=normal)" ] || fail "the working tree must be clean"
git remote get-url origin >/dev/null 2>&1 || fail "the origin remote is missing"
git remote get-url upstream >/dev/null 2>&1 || fail "the upstream remote is missing"
git show-ref --verify --quiet refs/heads/trunk || fail "the local trunk branch is missing"

printf 'Fetching origin/trunk and upstream/main...\n'
git fetch --prune origin '+refs/heads/trunk:refs/remotes/origin/trunk'
git fetch --prune upstream '+refs/heads/main:refs/remotes/upstream/main'

git merge-base --is-ancestor origin/trunk trunk || fail "origin/trunk contains changes that are not in local trunk"
git merge-base --is-ancestor trunk upstream/main || fail "local trunk cannot be fast-forwarded to upstream/main"

if [ "$(git rev-parse trunk)" = "$(git rev-parse upstream/main)" ]; then
	printf 'Local trunk is already synchronized with upstream/main.\n'
else
	printf 'Incoming upstream commits:\n'
	git log --oneline --decorate trunk..upstream/main
fi

git switch --quiet trunk
git merge --ff-only upstream/main
git push origin trunk
printf 'Published local trunk to origin/trunk.\n'
