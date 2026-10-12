#!/usr/bin/env bash
# Ensure Ansible and this repo's Galaxy dependencies are installed.
# The distro package manager only provides uv; uv then installs Ansible as a
# user-level tool, so every distro gets the same Ansible version.
set -euo pipefail

cd "$(dirname "$0")/.."

install_uv() {
    if command -v pacman >/dev/null 2>&1; then
        echo "Info:     Installing uv using pacman"
        # -Syu rather than -Sy: partial upgrades are unsupported on Arch.
        sudo pacman -Syu --needed --noconfirm uv
    elif command -v dnf >/dev/null 2>&1; then
        echo "Info:     Installing uv using dnf"
        sudo dnf install -y uv
    elif command -v apt-get >/dev/null 2>&1; then
        sudo apt-get update
        if apt-cache show uv >/dev/null 2>&1; then
            echo "Info:     Installing uv using apt"
            sudo apt-get install -y uv
        else
            echo "Error:    UV is not packaged with your apt utilizing distribution" >&2
            exit 1
        fi
    else
        echo "Error:    No supported package manager found (pacman, dnf, apt)" >&2
        exit 1
    fi
}

# The official installer puts uv in ~/.local/bin, which may not be on PATH yet.
export PATH="$HOME/.local/bin:$PATH"

if command -v ansible-playbook >/dev/null 2>&1; then
    echo "Info:     Ansible already installed"
else
    if command -v uv >/dev/null 2>&1; then
        echo "Info:     uv already installed"
    else
        install_uv
    fi

    echo "Info:     Installing Ansible using uv"
    uv tool install --with-executables-from ansible-core ansible
    PATH="$(uv tool dir --bin):$PATH"
fi

echo "Info:     Installing Galaxy collections/roles from requirements.yml"
ansible-galaxy install -r requirements.yml
