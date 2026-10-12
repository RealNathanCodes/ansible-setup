#!/usr/bin/env bash
# Self-bootstrap: install Ansible, collect user vars, then run site.yml
# against the whole inventory. Extra args are passed through to
# ansible-playbook, e.g.
#   ./run.sh -l desktops
#   ./run.sh -l main-laptop --tags starship
set -euo pipefail

cd "$(dirname "$0")"

# uv-installed Ansible lives in uv's tool bin dir (usually ~/.local/bin).
export PATH="$HOME/.local/bin:$PATH"
if command -v uv >/dev/null 2>&1; then
    PATH="$(uv tool dir --bin):$PATH"
fi

if ! ./scripts/bootstrap.sh; then
    echo "Error:    Bootstrapping Ansible failed. Resolve the errors above and try again." >&2
    exit 1
fi

echo "Info:     Loading user variables..."
if ! ./scripts/set_user_variables.sh; then
    echo "Error:    Setting user variables failed. Run ./scripts/set_user_variables.sh and resolve the errors." >&2
    exit 1
fi

# Per-host sudo passwords live vault-encrypted in the git-ignored
# secrets/host_vars/*/become.yml and override the --ask-become-pass answer for
# those hosts. Only ask for the vault password when there is something to
# decrypt, so a fresh clone without secrets/ still runs.
vault_args=()
if [ -s secrets/vault_pass ]; then
    vault_args=(--vault-password-file secrets/vault_pass)
elif compgen -G 'secrets/host_vars/*/become.yml' >/dev/null; then
    vault_args=(--ask-vault-pass)
fi

echo "Info:     Running playbook..."
ansible-playbook site.yml --ask-become-pass "${vault_args[@]}" "$@"
