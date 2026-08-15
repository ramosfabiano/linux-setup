# Debian — distro specifics

Companion to `../SKILL.md`, which holds the actual procedure. This file only
covers what differs on Debian.

| | |
|---|---|
| Script | `debian-NN-setup.sh` |
| Base image | `docker.io/library/debian:NN` |
| Package manager | `apt` |
| Install | `apt install -y <pkg>` |
| Remove | `apt remove -y <pkg>` |
| Query installed | `dpkg -l <pkg>` (prints `no packages found matching <pkg>` when absent) |
| Repo files | `/etc/apt/sources.list.d/*.sources` (deb822) and `*.list` |
| `ncurses` for `tput` | `apt install -y ncurses-bin` |

Verified on the `debian:13` base image: `dpkg -l systemd` → *no packages found
matching systemd*, and no `/sbin/init` or `/usr/lib/systemd/systemd`, so run
the container with `sleep infinity`. Note systemd may get pulled in later as a
dependency of something the script installs — that does not give you a running
PID 1.

## Conflict behaviour — the important difference

**`apt` resolves conflicts by auto-removing the conflicting package** and
completing the transaction, where `dnf` would abort (see `fedora.md`).

Measured: with `power-profiles-daemon` pre-installed, the script's
`apt install -y tlp tlp-rdw smartmontools` completed successfully and left
`power-profiles-daemon` in state `rc` (removed, config remaining). Debian's
`tlp` declares `Conflicts: laptop-mode-tools, power-profiles-daemon, tuned`,
same as Fedora's — but the outcome is completely different.

**Consequence:** the install-before-remove ordering bug that was fatal on
Fedora is *not* a bug here, and the script's trailing
`apt remove power-profiles-daemon -y` is merely a no-op. Do not "fix" it.
Reproduce a failure on Debian before changing Debian code.

Because `apt` runs a real dependency solve, also watch for the opposite
failure mode: a conflict resolved by removing something you *wanted* to keep.
Check `dpkg -l` after, don't just trust the exit status.

## Debian-only container artifacts

Add these to the shared "Expected non-bugs" list:
- `invoke-rc.d: could not determine current runlevel` and
  `invoke-rc.d: policy-rc.d denied execution of reload` during postinst
  scriptlets — no init in the container.
- `debconf: delaying package configuration, since apt-utils is not installed`
  on minimal images.
- `setup_fonts` preseeds the msttcorefonts EULA via `debconf-set-selections`;
  it needs no TTY and should not prompt. A prompt appearing *is* a real bug.

## Distro notes that affect testing

- `update_system` runs `apt modernize-sources -y`, which rewrites
  `sources.list` into deb822 `sources.list.d/debian.sources` and then appends
  `contrib non-free` to `Components:`. If a later step reports missing
  packages, check that rewrite landed before blaming the package name.
- `setup_zram` manipulates `/etc/fstab`, `swapon`/`swapoff` and a specific
  `/dev/dm-2`. That is host-storage-dependent and cannot be validated in a
  container — treat any result from it as meaningless (see "What a container
  cannot tell you" in `SKILL.md`).
- `install_backports_repo` adds trixie-backports; a failure here shows up much
  later as an unexpected package version, not as an error at the time.

## Positive verification worth running

```bash
podman exec <c> dpkg -l tlp tlp-rdw smartmontools power-profiles-daemon
podman exec <c> dpkg -l code cursor claude-code veracrypt podman
podman exec <c> flatpak list --columns=application
```
`dpkg -l` marks state in the first column: `ii` = installed, `rc` = removed
with config left behind. `rc` for `power-profiles-daemon` after a tlp install
is the expected, healthy outcome.
