# ansible-setup

Ansible playbooks for provisioning and maintaining both servers and
desktops/laptops across Arch-based, Fedora-based, and Ubuntu-based
distributions.

See [TODO.md](TODO.md) for the full build-out plan and scope decisions.

## Layout

- `site.yml` — single entry-point playbook, with separate plays for the
  `servers` and `desktops` inventory groups.
- `inventories/hosts.yml` — inventory. Add real hosts under the `servers` /
  `desktops` groups. Distro-family groups (`arch`, `fedora`, `ubuntu`) are not
  listed there: the first play in `site.yml` derives them from
  `ansible_os_family` with `group_by`, so `group_vars/arch.yml` etc. apply
  automatically. Because they're created at runtime, `-l arch` won't match;
  limit by host or by `servers`/`desktops` instead.
- `group_vars/`, `host_vars/` — variables per group/host. Nothing secret goes
  here; see `secrets/`.
  Shared vars for every host (`primary_user`, `ssh_authorized_keys`,
  `base_packages`) are in `group_vars/all/main.yml`. Use that directory, not a
  `group_vars/all.yml` file: Ansible ignores the file when the directory exists.
  Role vars that differ between servers and desktops (e.g.
  `podman_enable_linger`) go in `group_vars/servers.yml` /
  `group_vars/desktops.yml`.
- `secrets/` — git-ignored, never committed: SSH keys, the vault password and
  per-host secret vars (see below).
- `roles/` — this project's own roles.
- `galaxy_roles/` — third-party roles installed via `requirements.yml`
  (git-ignored, not vendored).
- `run.sh` — wrapper that installs Ansible if needed, then runs `site.yml`
  (see below).
- `scripts/bootstrap.sh` — installs uv via pacman/dnf/apt, uses it to
  install Ansible if it's missing, then installs the Galaxy requirements.
- `scripts/set_user_variables.sh` — prompts for git identity and writes
  `group_vars/all/user_variables.yml` (git-ignored, per machine).
- `scripts/set_become_password.sh` — stores a host's vault-encrypted sudo
  password in `secrets/host_vars/<host>/become.yml` (see below).

## Usage
Run against the whole inventory:

```
ansible-playbook site.yml
```

Scope to one host or group:

```
ansible-playbook site.yml -l desktops
ansible-playbook site.yml -l some-hostname
```

### Using run.sh

`run.sh` wraps the commands above:

```
./run.sh                                # whole inventory
./run.sh -l desktops                    # one group
./run.sh -l main-laptop                 # one host
./run.sh -l main-laptop --tags starship # one role on one host
```

`run.sh` installs Ansible if needed (see below), prompts for user variables
on first run, then runs `site.yml --ask-become-pass` with any extra arguments
passed through to `ansible-playbook`. The sudo password you enter is used for
every host in the run that has no password of its own (see below). Plays only
target the `servers`/`desktops` groups, so a host must be a member of one of
them to have anything applied.

There is no `localhost` entry. The machine you run from is reached over SSH
like any other host, so to configure it, list it in `inventories/hosts.yml`
under its own name (with `sshd` running and your key authorized) and limit to
that name.

### Secrets

Anything secret lives in `secrets/`, which git ignores. Keep it outside the
repo (for example as a zip in a password manager) and unzip it into the repo
root on each control node:

```
secrets/
├── hosts.yml                  # empty inventory source; anchors host_vars/
├── vault_pass                 # vault password
├── ssh/testserver             # SSH private keys (must be mode 600)
└── host_vars/test-server/become.yml
```

`ansible.cfg` lists `secrets/hosts.yml` as a second inventory source, so
`secrets/host_vars/` is loaded the same way as `host_vars/`. Without
`secrets/`, Ansible warns that it can't parse that source and carries on.
Inventory entries point at keys with
`"{{ ansible_config_file | dirname }}/secrets/ssh/<key>"`, which resolves from
any working directory.

Hosts that don't share your local sudo password get their own, stored
vault-encrypted as `ansible_become_password`:

```
./scripts/set_become_password.sh test-server
```

The first run creates `secrets/hosts.yml` and `secrets/vault_pass`. A host's
own password takes precedence over the `--ask-become-pass` answer. `run.sh`
passes `secrets/vault_pass` automatically; plain `ansible`/`ansible-playbook`
commands against those hosts need `--vault-password-file secrets/vault_pass`.
Re-zip and re-upload `secrets/` after any change.

### How Ansible gets installed

`scripts/bootstrap.sh` keeps whatever `ansible-playbook` is already on `PATH`.
Otherwise it:

1. Installs [uv](https://docs.astral.sh/uv/) with the distro package manager
   (pacman, dnf, or apt). On Debian/Ubuntu releases that don't package uv, it
   fails.
2. Runs `uv tool install --with-executables-from ansible-core ansible`. This
   installs Ansible for your user in uv's tool bin dir (usually
   `~/.local/bin`), so every distro gets the same version and no system Python
   packages are touched.

`run.sh` adds that directory to `PATH` itself. To run `ansible-playbook`
directly, make sure `~/.local/bin` is on your `PATH` (`uv tool update-shell`
can do this). Upgrade later with `uv tool upgrade ansible`.

`--with-executables-from` needs a recent uv (0.8 or later). If your distro's
uv is older, `uv tool install ansible-core` works too, since
`requirements.yml` already installs the collections this repo uses.

## Roles

| Role | Tags | Applies to | What it does |
|------|------|------------|--------------|
| `starship` | `starship`, `shell` | desktops | Installs starship (pacman on Arch, upstream installer elsewhere), deploys `~/.config/starship.toml`, adds init to fish (`conf.d/starship.fish`) and bash (managed block in `~/.bashrc`). |
