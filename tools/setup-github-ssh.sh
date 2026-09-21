#!/bin/bash
set -euo pipefail

fail() {
	printf 'setup-github-ssh: %s\n' "$1" >&2
	exit 1
}

repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || fail "run this command from inside the repository"
cd "$repo_root"

[ "$(git symbolic-ref --quiet --short HEAD)" = "containerized" ] || fail "the containerized branch must be checked out"
git remote get-url origin >/dev/null 2>&1 || fail "the origin remote is missing"
email=$(git config --get user.email) || fail "Git user.email is not configured"

key_path=${GITHUB_SSH_KEY:-"$HOME/.ssh/id_ed25519"}
public_key_path="$key_path.pub"
key_directory=$(dirname "$key_path")

if [ -e "$key_path" ] || [ -e "$public_key_path" ]; then
	[ -f "$key_path" ] && [ -f "$public_key_path" ] || fail "both $key_path and $public_key_path must exist to reuse the key"
	printf 'Reusing existing SSH key: %s\n' "$key_path"
else
	mkdir -p "$key_directory"
	chmod 700 "$key_directory"
	printf 'Creating SSH key: %s\n' "$key_path"
	ssh-keygen -t ed25519 -C "$email" -f "$key_path"
fi

agent_status=0
ssh-add -l >/dev/null 2>&1 || agent_status=$?
if [ "$agent_status" -eq 2 ]; then
	eval "$(ssh-agent -s)" >/dev/null
elif [ "$agent_status" -gt 2 ]; then
	fail "could not inspect ssh-agent"
fi
ssh-add "$key_path"

printf '\nAdd this public key to GitHub:\n\n'
cat "$public_key_path"
printf '\n\nGitHub SSH key settings: https://github.com/settings/keys\n'
if command -v xdg-open >/dev/null 2>&1; then
	xdg-open https://github.com/settings/keys >/dev/null 2>&1 || true
fi
printf 'After adding the public key to GitHub, press Enter to continue: '
read -r

auth_output=$(ssh -o StrictHostKeyChecking=accept-new -o BatchMode=yes -T git@github.com 2>&1 || true)
printf '%s\n' "$auth_output"
case "$auth_output" in
	*"Hi jbandholz! You've successfully authenticated"*) ;;
	*) fail "GitHub SSH authentication as jbandholz did not succeed" ;;
esac

ssh_origin=git@github.com:jbandholz/mailinabox-containerized.git
git remote set-url origin "$ssh_origin"
git push origin containerized
git fetch origin '+refs/heads/containerized:refs/remotes/origin/containerized'

local_commit=$(git rev-parse containerized)
remote_commit=$(git rev-parse origin/containerized)
[ "$local_commit" = "$remote_commit" ] || fail "origin/containerized does not match local containerized after push"

printf 'GitHub SSH authentication is configured.\n'
printf 'Published containerized at %s.\n' "$local_commit"
