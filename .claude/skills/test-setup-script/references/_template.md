# <Distro> — distro specifics

Companion to `../SKILL.md`, which holds the actual procedure. This file only
covers what differs on <Distro>. Copy this template, fill it in, and add a row
to the table at the top of `SKILL.md`.

| | |
|---|---|
| Script | `<distro>-NN-setup.sh` |
| Base image | `<registry>/<image>:NN` |
| Package manager | `<dnf/apt/zypper/pacman/...>` |
| Install | `<cmd>` |
| Remove | `<cmd>` |
| Query installed | `<cmd>` (and what it prints when the package is absent) |
| Repo files | `<path glob>` |
| `ncurses` for `tput` | `<cmd>` |

## Before trusting the shared procedure — check these

1. **Does the script follow the shared skeleton?** It needs `main` → menu →
   `auto()`, plus `msg()`, `ask_reboot()`, and the trailing
   `(return 2> /dev/null) || main`. The whole "How the README actually invokes
   these" section in `SKILL.md` (menu-via-stdin, trailing `q`, `tee` masking
   `$?`) is derived from that skeleton. If it differs, re-derive rather than
   assume.
2. **Is this distro testable in a container at all?** Atomic/image-based
   distros (`rpm-ostree`, `transactional-update`) do not install into a
   running container the way `dnf`/`apt` do, so a green run would prove
   nothing. Say so instead of reporting success.
3. **Does the base image have an init?** Check the package and
   `/sbin/init` + `/usr/lib/systemd/systemd`. If absent (the usual case), run
   with `sleep infinity` and expect the shared systemd/D-Bus artifacts.

## Conflict behaviour

How does this package manager handle a conflict — abort the transaction like
`dnf`, or auto-remove the conflicting package like `apt`? **Determine this
empirically, do not assume**, then record the log signature here. It decides
whether install-before-remove ordering is a real bug on this distro.

## <Distro>-only container artifacts

List messages that look like failures but are container/minimal-image
artifacts, so future runs don't re-report them.

## Bugs found and fixed here

Record real bugs with the failing signature and the fix, so a regression is
recognisable.

## Positive verification worth running

```bash
podman exec <c> <query-installed> <key packages>
podman exec <c> flatpak list --columns=application
```
State what a healthy run looks like.
