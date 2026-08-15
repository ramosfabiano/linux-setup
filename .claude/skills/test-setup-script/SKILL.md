---
name: test-setup-script
description: Test one of this repo's distro post-install setup scripts (fedora-44-setup.sh, debian-13-setup.sh, or any other <distro>-NN-setup.sh) end-to-end in a disposable podman container, verify a fix after editing one, and clean up leaving no leftover containers or images. Use when asked to test, verify, validate, re-check or reproduce a bug in a setup script, or right after changing one.
globs:
alwaysApply: false
---
# Testing a distro setup script in a container

This file is the whole procedure and applies to **every** distro. Only the
package-manager details differ, and those live in one small file per distro.

**Before starting, read the reference for the distro you're testing** — the
agent must open it explicitly, it is not auto-loaded:

| Distro | Script | Base image | Pkg mgr | Query installed | Reference |
|---|---|---|---|---|---|
| Fedora | `fedora-NN-setup.sh` | `registry.fedoraproject.org/fedora:NN` | `dnf` | `rpm -q <pkg>` | `.claude/skills/test-setup-script/references/fedora.md` |
| Debian | `debian-NN-setup.sh` | `docker.io/library/debian:NN` | `apt` | `dpkg -l <pkg>` | `.claude/skills/test-setup-script/references/debian.md` |

Adding a distro? See "Adding a new distro" at the bottom and copy
`.claude/skills/test-setup-script/references/_template.md`.

## Why running it beats reading it

These scripts are root-only, function-based bash: each package step lives in
its own function, and `auto()` runs them in a fixed order. No script sets
`set -e` internally, so how failures behave depends entirely on how the script
is *invoked*. Read "How the README actually invokes these" before interpreting
any result.

Containers are close enough to bare metal for package-manager work (installs,
repo setup, flatpak, downloads + GPG verification). Two categories can't be
judged from a container at all: systemd/D-Bus steps, and anything
hardware-dependent — see "Expected non-bugs" and "What a container cannot tell
you".

## How the README actually invokes these

Test the script the way it will really be run. Every distro's README line has
the same shape:

```bash
sudo bash -e -o pipefail -c "$(wget -qO- .../<distro>-setup.sh) | tee log.txt"
```

**The `-e` is deliberate and must stay.** These scripts are meant to fail
fast: if any command in any function fails, the run is over. It is not
supposed to press on, recover, or be safe to re-run. Do not "fix" a
half-finished run by removing `-e`, and do not add idempotency guards on the
grounds that a second run would duplicate something — re-running after a
failure is not a supported flow. A truncated log is the design working.

Three consequences, all verified empirically — do not assume, they are
counter-intuitive:

1. **The script text is inlined by command substitution**, so `| tee log.txt`
   attaches to the script's *last line* only — `(return 2> /dev/null) || main`
   becomes `... || main | tee log.txt`. `return` fails when not sourced, so
   `main` runs: the **interactive menu**, not `auto()` directly.
2. **`-o pipefail` is what makes the exit status truthful, and must stay.**
   Without it the pipeline reports `tee`'s status — `0` even when the script
   aborted a third of the way in. With it, a failed run exits nonzero. It
   changes nothing inside the scripts: every pipeline there has a first stage
   that cannot fail on its own (`echo`/`cat`/`wget`-into-`gpg`, the last all
   already fatal under `-e`), so it introduces no new abort points.
3. **Driving the menu from stdin needs a trailing `q`.** Feed
   `printf '1\nn\nq\n'`: `1` runs `auto()`, `n` answers `ask_reboot`, `q`
   exits. Without the `q`, `read` hits EOF, `choice` stays empty, the `case`
   falls to `*` and the menu **loops forever** printing `[!] Wrong input!`.

### Testing under `-e`: use two runs

errexit is live inside `main`/`auto()` — verified, the first nonzero command
ends the run and later steps never execute. That is correct on real hardware,
but in a container it makes coverage impossible, because the systemd/D-Bus
calls fail for environmental reasons that would not occur on a real desktop.
So test with **two** runs:

- **Faithful run** — the exact README line, `-e` included. Tells you what a
  user really gets, and where it stops. Prime the container with `ncurses` and
  `TERM` first (step 2), or it dies on `msg()`'s own `tput` before any real
  work happens.
- **Coverage run** — same command with `-e` dropped, purely as a testing
  device so execution continues past container-only failures and the later
  functions actually get exercised. Never propose this as a change to the
  README.

**One real-hardware caveat worth reporting if you see it:** `msg()` calls
`tput` before every step, and `tput` returns nonzero when `TERM` is unset or
`dumb` — under `cron`, a non-TTY SSH session, or a `sudo` that does not
preserve `TERM`. Combined with `-e`, that aborts the run at the first banner
having done nothing. Interactively `TERM` is set and this does not arise.

All three consequences follow from the **shared script skeleton** (`main` →
menu → `auto()` → `msg()`/`ask_reboot`, plus the trailing
`(return 2> /dev/null) || main`), not from any distro. They hold only as long
as a script keeps that skeleton — see "Adding a new distro".

## Procedure

1. **Record which images already exist, before pulling anything** — cleanup in
   step 8 must not delete an image the user already had:
   ```bash
   podman images --format '{{.Repository}}:{{.Tag}}' | grep -iE 'fedora|debian|<distro>'
   ```
   Then take the base image from the table above.

   (`podman` is assumed throughout; `docker` on this host is an alias for it.)
   Budget ~3 GB of pulls/installs per full run — cursor and code are ~1 GB
   each installed, plus claude-code, qemu/libvirt and ffmpeg.

2. **Start a disposable container** and copy the script in:
   ```bash
   podman run -d --name <distro>-test <image> sleep infinity
   podman cp <script>.sh <distro>-test:/root/<script>.sh
   ```
   Optionally install `ncurses` (see the distro reference for the exact
   command) and export `TERM=xterm` so `msg()`'s `tput` works and the step
   banners render as they would on a real desktop; without it every `msg()`
   logs a harmless `tput: command not found`.

   Use `sleep infinity`, not the distro's init. Verified for both current base
   images: neither ships systemd (`rpm -q systemd` → *not installed*;
   `dpkg -l systemd` → *no packages found*) and neither has `/sbin/init` or
   `/usr/lib/systemd/systemd`, so there is no PID 1 to boot and
   `--systemd=always` buys nothing. Re-check this for a new distro.

3. **Run it the README way** (see above). Using the local working copy via
   `cat` is equivalent to the README's `wget -qO-` — both just inline the
   script text — and tests your uncommitted edits:
   ```bash
   # faithful run (-e, as the README has it); drop -e for the coverage run
   podman exec -d <distro>-test bash -c \
     'export TERM=xterm; printf "1\nn\nq\n" | bash -e -o pipefail -c "$(cat /root/<script>.sh) | tee /root/log.txt" \
        > /root/run.log 2>&1; echo "DONE_EXIT:$?" >> /root/run.log'
   ```
   A full run takes 10-15 minutes, so launch it detached (`exec -d`) and poll
   for the marker from a backgrounded Bash call rather than blocking the
   session:
   ```bash
   until podman exec <distro>-test grep -q '^DONE_EXIT:' /root/run.log; do sleep 10; done
   ```
   With `-e -o pipefail` the `DONE_EXIT:` value is now **meaningful**: nonzero
   means the run aborted. Still confirm *where* it stopped from the log (step
   5) — the exit code says a failure happened, not which function caused it.
   Note the coverage run (no `-e`) is the exception: there the value is just
   the last command's status and means nothing.

   To exercise one function in isolation instead, **source** the script —
   sourcing makes the trailing `return` succeed so the menu never fires:
   ```bash
   podman exec <distro>-test bash -c "source /root/<script>.sh; setup_tlp"
   ```

4. **Prefer whole-`auto()` runs over isolated functions.** Later functions
   rely on state earlier ones leave behind — `setup_fonts` and
   `install_veracrypt` call `wget` without installing it, because
   `install_packages` already did. Running one standalone in a fresh container
   yields a false `wget: command not found`. If you must isolate, recreate the
   ordering/state first, or treat the result as a rough signal only.

5. **Pull the log and triage.** `podman cp <distro>-test:/root/run.log ./`,
   then grep broadly and read the context around each hit — the grep is a
   starting point, not a verdict:
   ```bash
   grep -inE "error|fail|not found|no such|unable|cannot|denied|not installed|does not exist" run.log
   ```
   Sort every hit into "expected container artifact" (below, plus the distro
   reference's own list) or "real bug".

   **Always confirm the run reached the end**, rather than assuming it did —
   compare the step banners that actually ran against the `msg '...'` calls in
   `auto()`. When `TERM`/`ncurses` are present `msg()` wraps them in colour
   codes, so a plain `grep '^\[\*\]'` finds **nothing** — strip the escapes:
   ```bash
   grep -aoE '\[\*\] .*' run.log | sed 's/\x1b\[[0-9;]*m//g'
   grep -oE "msg '.*'" <script>.sh     # the expected sequence
   ```
   A healthy full run ends with `[*] Done!` having hit every step. Anything
   short of that means `-e` aborted the run there. **The last banner printed
   tells you which function failed**; that is the finding to report, since
   under `-e` everything after it never ran. On a faithful
   container run expect a stop at `[*] Setting up firewall` (the `systemctl`
   calls) — environmental, not a script bug.

6. **Confirm successes positively — absence of grep hits is weak evidence.**
   The decisive checks are direct queries (exact commands in the distro
   reference):
   ```bash
   podman exec <c> <query-installed> <pkg>
   podman exec <c> flatpak list
   ```
   This is what actually proved the flatpaks installed, that `tuned`/
   `tuned-ppd` were present by default, and that apt auto-removed
   `power-profiles-daemon`.

7. **After fixing a real bug, re-verify in a *fresh* container** — not the one
   that ran the broken version, where leftover package/repo state can make a
   non-fix look like a fix. Re-run the affected function(s) and confirm the
   specific failure signature is gone.

8. **Clean up unconditionally.** Containers first (force-remove; they are
   still "running" on `sleep infinity`), then only those images step 1 showed
   were absent beforehand:
   ```bash
   podman rm -f <distro>-test
   podman rmi <image>   # ONLY if step 1 showed it was not already present
   ```
   A `SIGTERM failed to stop container ... resorting to SIGKILL` warning here
   is expected and harmless. Removing a tag that shares an image ID with
   another tag (e.g. `debian:13` vs `debian:trixie`) only untags it.

9. **Report the outcome**, then offer the full log rather than pasting it —
   these run to several thousand lines. Say which functions passed, which
   failed for container-only reasons, and which are real bugs; ask before
   dumping the log.

## Expected non-bugs (container artifacts)

Distro-agnostic; the distro reference lists its own additions. Don't report
these as findings:
- `systemctl` / `firewall-cmd` → `System has not been booted with systemd as
  init system`, `Failed to connect to system scope bus`, `Failed to connect to
  socket /run/dbus/system_bus_socket`. No systemd/D-Bus PID 1.
- `flatpak install` → `bwrap: Creating new namespace failed: Operation not
  permitted`. Nested sandboxing is restricted; the flatpak still installs
  (confirm with `flatpak list`).
- `tput: command not found`, `xset: unable to open display`, `Failed to
  connect to audit log, ignoring`. Minimal image, no X, no audit subsystem.
- `Unit sshd.service does not exist` / `pcscd.service does not exist` — those
  packages aren't in a minimal image.

## What a container cannot tell you

Some steps *install cleanly and prove nothing*, because the container shares
the host's `/proc` and `/sys`:
- `install_qemu` (KVM), `setup_camera` (ipu6, `dmesg`), `setup_tlp` (battery
  thresholds, CPU governors) and the intel media drivers install fine, but
  their runtime behaviour is untested.
- Hardware-facing output can look convincingly real while describing the
  **host**: `tlp-stat -s` run inside a *Fedora* container reported
  `System = Dell Inc. XPS 13 9340`, `Kernel = 6.12.101+deb13-amd64` (the
  Debian host's kernel) and `Init system = sysvinit`. Don't read that as the
  container validating anything.

## Real bug patterns found this way

Distro-specific instances live in each reference. The transferable shapes:

- **Install-before-remove against a package-manager conflict**, and more
  generally **the same fix does not port across package managers**. Installing
  `tlp` before removing what it conflicts with is fatal under `dnf`, which
  hard-aborts the whole transaction, but harmless under `apt`, which
  auto-removed the conflicting package and completed. Always reproduce the
  failure on *that* distro before "fixing" it — assuming the Fedora bug also
  existed on Debian would have produced a pointless change to working code.
- **Reused config/repo identifiers across unrelated integrations.** Two repo
  files both claiming the same id — fragile even when it happens to still
  install. Give each a unique id.
- **Unguarded globs that don't expand when empty.**
  `for userpath in /home/*; do usermod -a -G libvirt,kvm $(basename $userpath); done`
  — with no match the glob stays literal and `usermod` fails with
  `user '*' does not exist`. Note this one is **latent on real hardware**
  (a desktop already has a home directory) and only surfaces in the empty
  container; still worth guarding with `shopt -s nullglob` or a `[ -d ... ]`
  test.

## Adding a new distro

1. Copy `.claude/skills/test-setup-script/references/_template.md` to
   `.claude/skills/test-setup-script/references/<distro>.md` and fill it in.
   (Paths here are relative to the repo root, so they resolve the same whether
   this file is read as the Claude Code skill or through the Cursor symlink.)
2. Add a row to the table at the top of this file.
3. **Check the script actually follows the shared skeleton** before trusting
   this procedure on it: it needs `main` → menu → `auto()`, `msg()`,
   `ask_reboot`, and the trailing `(return 2> /dev/null) || main`. If it
   diverges, the whole "How the README actually invokes these" section may not
   apply — re-derive it rather than assuming.
4. **Check the distro is testable this way at all.** An image-based or atomic
   distro (`rpm-ostree`, `transactional-update`) does not install packages
   into a running container the way `dnf`/`apt` do, so a container run would
   prove nothing. Say so rather than reporting a green run.
5. Confirm the base image's init situation as in step 2 (no systemd → use
   `sleep infinity`).
