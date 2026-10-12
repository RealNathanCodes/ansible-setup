# Ansible Setup — TODO

Scope decisions (from planning discussion on 2026-10-08):

- **Targets**: Arch-based, Fedora-based, Ubuntu-based distros. Both **servers** and **desktops/laptops**.
- **Execution mode**: support **both** — remote management of an inventory over SSH (control node + `become`), and local/self-bootstrap runs (e.g. `ansible-pull` or a `run.sh` wrapper targeting `localhost`) for a fresh desktop/laptop.
- **App install priority**: native package manager (pacman/dnf/apt) first → Flatpak (Flathub) second → Snap only as a last resort when not available in the other two. **Exception: Visual Studio Code is always installed via Snap**, regardless of availability elsewhere.
- **Firewall**: native tool per distro (ufw on Ubuntu, firewalld on Fedora, ufw for Arch), not a single standardized tool.
- **Extra scope**: server hardening (fail2ban, sshd config, auto-updates) is in scope. Shell/dotfiles setup (fish, starship, Nerd Fonts, git credential helper) is in scope too, based on prior art in `~/dev/computer_setup`.
- **Reference material**: `~/dev/computer_setup` has a previous (Ubuntu/Manjaro-only) attempt — reusable patterns for the VS Code role, snap bootstrap, git role w/ libsecret credential helper, fish/starship files, and the per-`ansible_os_family` package task pattern. Its firacode role is unfinished/broken — rewrite, don't copy.

---

## Phase 0 — Repo scaffolding
- [x] `git init`, `.gitignore` (vault pass files, `*.retry`, etc.)
- [x] `ansible.cfg` (roles_path, inventory path, `host_key_checking`, pipelining)
- [x] Directory layout: `inventories/`, `group_vars/`, `host_vars/`, `roles/`, `galaxy_roles/`, top-level `site.yml` (single playbook, not a `playbooks/` subdir — finalized here, see Phase 8 note)
- [x] `requirements.yml` for Galaxy collections (`community.general`, `ansible.posix`)
- [x] README describing layout and how to run, including `run.sh` and the SSH-only (no local mode) approach

## Phase 1 — Inventory & host classification
- [x] Define inventory groups: `servers`/`desktops` are hand-maintained in `inventories/hosts.yml`; `arch`/`fedora`/`ubuntu` are derived at runtime by a `group_by` classification play at the top of `site.yml` (`Archlinux`→`arch`, `RedHat`→`fedora`, `Debian`→`ubuntu`; unsupported families fail fast). Note: plain Debian lands in `ubuntu` and RHEL/Rocky/Alma in `fedora`
- [x] Shared vars for all hosts — `group_vars/all/main.yml` (not `group_vars/all.yml`: Ansible ignores the `.yml` file when the `all/` directory exists, and the directory holds the git-ignored `user_variables.yml` with git name/email). Defines `primary_user` (now the default for `podman_user`/`starship_user`), `ssh_authorized_keys` (empty; consumed in Phase 6) and `base_packages` (cross-distro names; consumed in Phase 2)
- [x] `group_vars/servers.yml` / `group_vars/desktops.yml` for role-specific vars — servers set `podman_enable_linger: true` (rootless containers otherwise stop when the last SSH session closes); desktops state the `false` default explicitly. Later phases add their per-group vars here (e.g. firewall ports in Phase 3)
- [x] No `ansible_connection: local` entry: the `local` group/`localhost` was removed, and every host, the control node included, is listed by name and reached over SSH. Avoids whole-inventory runs touching whichever machine you run from, and avoids a named host with `connection: local` silently configuring the wrong machine. `run.sh` has no local mode
- [x] `run.sh` for the local self-bootstrap path — ported from `computer_setup/scripts`; the three `install_ansible_*.sh` scripts are collapsed into `scripts/bootstrap.sh`, and `scripts/set_user_variables.sh` now writes `group_vars/all/user_variables.yml`
- [x] Main laptop added to `desktops` as `main-laptop` (`10.42.10.218`); `run.sh -l main-laptop` targets it

## Phase 2 — Common/base role (all hosts, all distros)
- [ ] OS family detection vars (map `ansible_os_family` → package manager, firewall tool, snap/flatpak bootstrap needs)
- [ ] System update task per distro (pacman/dnf/apt — same pattern as `computer_setup` `uptodate` role, but fix the existing bug where RedHat/Arch branches both call the `pacman` module instead of `dnf`/`yum`)
- [ ] Base package set (git, curl, vim/editor, etc.) per distro

## Phase 3 — Firewall role
- [ ] Ubuntu → `ufw` (enable, default deny incoming, allow SSH, allow additional ports via var list)
- [ ] Fedora → `firewalld` (ansible.posix.firewalld module, zones, services/ports via var list)
- [ ] Arch → `ufw`, but explicitly install `iptables-nft` instead of plain `iptables` (Arch's default `iptables` is still the legacy xtables implementation, unlike Ubuntu where `iptables` has been the nft-backed build since 20.10 — without this swap, Arch's ufw would run on legacy iptables while Ubuntu/Fedora run on nftables)
- [ ] Common var interface across all three (e.g. `firewall_allowed_tcp_ports`, `firewall_allowed_udp_ports`) so server/desktop group_vars can declare ports without caring which backend runs
- [ ] Server-specific firewall defaults (deny-by-default, only SSH + explicit service ports) vs desktop defaults (more permissive / or just SSH off by default)

## Phase 4 — Application installation framework
- [ ] Package-manager abstraction: role/vars mapping desired app name → native package name per distro (where available)
- [ ] Flatpak bootstrap role: install `flatpak`, add Flathub remote, per-distro package name differences
- [ ] Snap bootstrap role: install `snapd` per distro (fix the existing bug where the Fedora/RedHat branch also calls the `pacman` module instead of `dnf`), enable `snapd.socket`, symlink `/snap` on distros that need it (notably Fedora)
- [ ] Decision logic: for a given app, try native → flatpak → snap, **except VS Code which always goes through snap**
- [ ] VS Code role: snap install (`classic: yes`), `settings.json` deployment, extensions list install loop (carry over/extend extension list from `computer_setup`)
- [ ] Define the actual desktop app list (carry over gimp, krita, slack, handbrake, k3b, kid3, makemkv from `computer_setup`? confirm which are still wanted) and which install source each uses
- [x] Containers: **podman + podman-compose instead of Docker**, rootless only — `roles/podman` (installs per distro, allocates `/etc/subuid`/`/etc/subgid` ranges for the user, keeps the rootful `podman.socket` disabled, refuses `podman_user: root`; optional `podman_enable_linger` for servers). Applied to both servers and desktops
- [ ] Server app list (if any, beyond podman)

## Phase 5 — Shell / dotfiles / dev environment
- [ ] Fish shell install role (per distro)
- [x] Starship prompt install + config deployment — `roles/starship` (ported `starship.toml`; fish/bash init via conf.d snippet / `.bashrc` managed block; WSL `git.exe` wrapper only deployed on WSL)
- [ ] Fish role should set fish as the login shell (`chsh`) — replaces the old `.bashrc` `exec fish` hack, which was intentionally not ported
- [ ] Nerd Font install role (rewrite `firacode` role from scratch — the existing one is incomplete/non-functional: fix the loop-over-fonts structure, checksum, archive path mismatch)
- [ ] Git role: install git + libsecret/gnome-keyring, build/configure the libsecret credential helper, template `.gitconfig` from `git_name`/`git_email`/`github_username` vars (reuse pattern from `computer_setup/playbooks/roles/git`)
- [ ] Node.js role (if still wanted — carry over from old repo)

## Phase 6 — Server hardening
- [ ] SSH hardening (disable root login, disable password auth where keys are deployed, non-default port optional)
- [ ] fail2ban install + jail config (at least sshd jail)
- [ ] Automatic security updates per distro (`unattended-upgrades` on Ubuntu, `dnf-automatic` on Fedora, equivalent timer/pacman hook on Arch — Arch has no built-in unattended upgrade mechanism, decide on a cron/systemd-timer approach or explicitly skip)
- [ ] Confirm whether fail2ban/auto-updates should also apply to desktops or stay server-only

## Phase 7 — User/secrets handling (needed to support the above, even though not separately called out)
- [x] User variables file equivalent to `computer_setup/playbooks/vars/user_variables.yml` — `group_vars/all/user_variables.yml`, generated by `scripts/set_user_variables.sh`, git-ignored
- [x] Per-host sudo passwords via `ansible-vault` — `scripts/set_become_password.sh <host>` writes an encrypted `ansible_become_password` to `secrets/host_vars/<host>/become.yml`. `secrets/` (SSH keys, `vault_pass`, secret host_vars) is git-ignored and backed up as a zip in Bitwarden; it is loaded as a second inventory source (`secrets/hosts.yml`) so its `host_vars/` apply
- [ ] Other secrets (WiFi passwords, API keys) — reuse the same `.vault_pass` if any show up

## Phase 8 — Playbook composition & tagging
- [ ] Top-level playbook(s) wiring roles together per host group (servers get base + firewall + hardening + minimal apps; desktops get base + firewall + apps + shell/dotfiles + VS Code)
- [ ] Tag every role (mirroring `--tags` usage in the old repo) so partial runs are possible
- [x] Servers vs desktops structure: decided in Phase 0 — one `site.yml` with `hosts: servers`/`hosts: desktops` plays, both currently empty `roles: []` pending later phases

## Phase 9 — Validation
- [ ] `ansible-lint` / `yamllint` config
- [ ] Test runs against at least one real or VM instance per distro family (Arch, Fedora, Ubuntu) for both a "server" and "desktop" role assignment
- [ ] Idempotency check (second run should report no changes)

## Open questions to resolve before/during implementation
- [ ] Final desktop app list — keep all of gimp/krita/slack/handbrake/k3b/kid3/makemkv, or trim?
- [ ] Any Arch/Fedora-specific apps not relevant on Ubuntu, or vice versa?
- [x] Containers — podman/podman-compose (rootless) replaces Docker; on both servers and desktops. `podman_enable_linger: true` is set in `group_vars/servers.yml`
- [ ] Should auto-updates/fail2ban extend to desktops, or stay server-only?
