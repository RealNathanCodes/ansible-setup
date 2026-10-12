#!/usr/bin/env bash
# Store a host's sudo password as a vault-encrypted ansible_become_password in
# secrets/host_vars/<host>/become.yml, so each host can have its own password.
# secrets/ is git-ignored and kept outside the repo (e.g. as a zip in a
# password manager); its vault password file is created on first use.
#   ./scripts/set_become_password.sh test-server
set -euo pipefail

cd "$(dirname "$0")/.."

export PATH="$HOME/.local/bin:$PATH"

if [ $# -ne 1 ]; then
    echo "Usage:    $0 <inventory-hostname>" >&2
    exit 1
fi

HOST="$1"
SECRETS_DIR="secrets"
VAULT_PASS_FILE="${SECRETS_DIR}/vault_pass"
INVENTORY_FILE="${SECRETS_DIR}/hosts.yml"
VAR_FILE="${SECRETS_DIR}/host_vars/${HOST}/become.yml"

(umask 077; mkdir -p "$SECRETS_DIR")

# ansible.cfg lists this file as an inventory source; it only needs to exist
# so Ansible loads secrets/host_vars/ alongside it.
if [ ! -f "$INVENTORY_FILE" ]; then
    printf -- '---\n# Anchors secrets/host_vars/; hosts are defined in inventories/hosts.yml.\nall: {}\n' > "$INVENTORY_FILE"
fi

if [ ! -s "$VAULT_PASS_FILE" ]; then
    # Existing become.yml files were encrypted with some other vault password;
    # minting a new one here would leave them undecryptable.
    if compgen -G "${SECRETS_DIR}/host_vars/*/become.yml" >/dev/null; then
        echo "Error:    ${VAULT_PASS_FILE} is missing but encrypted become.yml files exist. Restore ${VAULT_PASS_FILE} first." >&2
        exit 1
    fi
    read -rsp 'New vault password: ' vault_pass; echo
    read -rsp 'Confirm vault password: ' vault_pass_confirm; echo
    if [ -z "$vault_pass" ] || [ "$vault_pass" != "$vault_pass_confirm" ]; then
        echo "Error:    Vault passwords are empty or do not match" >&2
        exit 1
    fi
    (umask 077; printf '%s\n' "$vault_pass" > "$VAULT_PASS_FILE")
    echo "Info:     Wrote ${VAULT_PASS_FILE}"
fi

read -rsp "Sudo password for ${HOST}: " become_pass; echo
read -rsp 'Confirm sudo password: ' become_pass_confirm; echo
if [ -z "$become_pass" ] || [ "$become_pass" != "$become_pass_confirm" ]; then
    echo "Error:    Sudo passwords are empty or do not match" >&2
    exit 1
fi

mkdir -p "$(dirname "$VAR_FILE")"
{
    echo '---'
    printf '%s' "$become_pass" \
        | ansible-vault encrypt_string --vault-password-file "$VAULT_PASS_FILE" \
            --stdin-name ansible_become_password
} > "$VAR_FILE"

echo "Info:     Wrote ${VAR_FILE} (back up ${SECRETS_DIR}/ again)"
