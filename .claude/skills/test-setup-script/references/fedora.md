# Fedora — distro specifics

Companion to `../SKILL.md`, which holds the actual procedure. This file only
covers what differs on Fedora.

| | |
|---|---|
| Script | `fedora-NN-setup.sh` |
| Base image | `registry.fedoraproject.org/fedora:NN` |
| Package manager | `dnf` |
| Install | `dnf -y install <pkg>` |
| Remove | `dnf -y remove <pkg>` |
| Query installed | `rpm -q <pkg>` (prints `package <pkg> is not installed` when absent) |
| Repo files | `/etc/yum.repos.d/*.repo` |
| `ncurses` for `tput` | `dnf -y install ncurses` |

Verified on the `fedora:44` base image: `rpm -q systemd` → *not installed*, and
no `/sbin/init` or `/usr/lib/systemd/systemd`, so run the container with
`sleep infinity`.

## Conflict behaviour — the important difference

**`dnf` hard-aborts the entire transaction on a package conflict.** Nothing in
the transaction is applied, and the run continues to the next command with the
packages simply missing. This is what makes install-before-remove ordering a
real bug on Fedora, where the same code is harmless on Debian (see
`debian.md`). The signature in a log:

```
Problem 1: problem with installed package
  - installed package tuned-2.27.0-1.fc44.noarch conflicts with tuned provided by tlp-...
  - cannot install the best candidate for the job
...
Transaction failed: Rpm transaction failed.
  - file /usr/share/dbus-1/system-services/net.hadess.PowerProfiles.service from install of
    tlp-... conflicts with file from package tuned-ppd-...
```

## Fedora-only container artifacts

Add these to the shared "Expected non-bugs" list:
- `sed: can't read /etc/selinux/config: No such file or directory` and
  `setenforce: SELinux is disabled`, from `install_qemu` — no SELinux config
  in the image.
- The package name `perl-Error` matches the triage grep for "error". Noise.
- Dozens of `Failed to connect to audit log, ignoring: Invalid argument` lines
  from rpm scriptlets.
- `repomd.xml GPG signature verification error: Signing key not found` during
  a metadata refresh of the Cursor repo. Non-fatal; the key imports and the
  install proceeds.
- `install_veracrypt` calls `sudo dnf` while already running as root. Works
  (`sudo` is in the image) and is harmless, but it is a real inconsistency in
  the script.

## Bugs found and fixed here

- **`setup_tlp` installed before removing conflicts.** Fedora 44 ships
  `tuned` + `tuned-ppd` by default; `tlp` conflicts with both on dbus service
  files. The script removed `power-profiles-daemon`, which is *not* the
  package that ships those files on Fedora 44 (`tuned-ppd` is), so the install
  aborted and TLP was silently never installed. Fix: remove
  `tuned tuned-ppd power-profiles-daemon` *before* installing `tlp`.
- **Duplicate repo id.** `cursor.repo` and `vscode.repo` both declared
  `[code]`. Fixed by renaming Cursor's to `[cursor]`. Verify with:
  ```bash
  podman exec <c> grep -h '^\[' /etc/yum.repos.d/cursor.repo /etc/yum.repos.d/vscode.repo
  ```

## Positive verification worth running

```bash
podman exec <c> rpm -q tlp tlp-rdw smartmontools tuned tuned-ppd
podman exec <c> rpm -q cursor code claude-code veracrypt podman
podman exec <c> flatpak list --columns=application
```
A good run shows `tlp` present with `tuned`/`tuned-ppd` *not installed*, and
zero occurrences of `conflicts with file from package` in the log.
