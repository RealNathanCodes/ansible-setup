#!/usr/bin/env bash
# Prompt for per-user settings (git identity, etc.) and write them to a
# git-ignored vars file. Skips if the file already exists; delete it to re-run.
set -euo pipefail

cd "$(dirname "$0")/.."

VAR_FILE="group_vars/all/user_variables.yml"

if [ -s "$VAR_FILE" ]; then
    echo "Info:     ${VAR_FILE} already exists, skipping"
    exit 0
fi

mkdir -p "$(dirname "$VAR_FILE")"

read -rp 'Git Name: ' git_name
read -rp 'Git Email: ' git_email
read -rp 'Github Username: ' github_username

{
    echo '---'
    [ -n "$git_name" ] && echo "git_name: \"$git_name\""
    [ -n "$git_email" ] && echo "git_email: \"$git_email\""
    [ -n "$github_username" ] && echo "github_username: \"$github_username\""
} > "$VAR_FILE"

echo "Info:     Wrote ${VAR_FILE}"
