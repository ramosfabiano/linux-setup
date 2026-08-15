---
name: test-setup-script
description: Test one of this repo's distro post-install setup scripts (fedora-44-setup.sh, debian-13-setup.sh, or any other <distro>-NN-setup.sh) end-to-end in a disposable podman container, verify a fix after editing one, and clean up leaving no leftover containers or images. Use when asked to test, verify, validate, re-check or reproduce a bug in a setup script, or right after changing one.
globs:
alwaysApply: false
---
# Testing a distro setup script in a container

This file is the whole procedure and applies to **every** distro; only
package-manager details differ, and those live in one file per distro.

## The contract

1. If **any** command in **any** function fails, the whole run has failed.
   Execution stops there; nothing after it runs.
2. There is no recovery and no resuming. A failed run is simply over.
3. The scripts are **not** idempotent and are not meant to be. They assume a
   clean starting state and may only be run once against it.
4. Therefore every run — real or test — starts from a **fresh** machine or
   container. To run again, throw the environment away and start over.

Do not "fix" a half-finished run by removing `-e`, and do not add idempotency
guards on the grounds that a second run would duplicate something: a second
run is not a supported flow. A truncated log is the design working, and the
step it stopped at is the finding.

Containers are close enough to bare metal for package-manager work, but cannot
judge systemd/D-Bus steps or anything hardware-dependent — see "Expected
non-bugs" and "What a container cannot tell you".

**Before starting, read the reference for the distro you're testing** — it is
not auto-loaded:

| Distro | Script | Base image | Pkg mgr | Query installed | Reference |
|---|---|---|---|---|---|
| Fedora | `fedora-NN-setup.sh` | `registry.fedoraproject.org/fedora:NN` | `dnf` | `rpm -q <pkg>` | `.claude/skills/test-setup-script/references/fedora.md` |
| Debian | `debian-NN-setup.sh` | `docker.io/library/debian:NN` | `apt` | `dpkg -l <pkg>` | `.claude/skills/test-setup-script/references/debian.md` |

Adding a distro? See "Adding a new distro" at the bottom and copy
`.claude/skills/test-setup-script/references/_template.md`.

## How the README invokes these

The scripts are root-only, function-based bash: each package step is a
function, and `auto()` runs them in a fixed order. No script sets `set -e`
internally — the `-e` in the README line is what enforces the contract above,
so test the script the way it is really run:

```bash
sudo bash -e -o pipefail -c "$(wget -qO- .../<distro>-setup.sh) | tee log.txt"
```

Three consequences, all verified empirically — do not assume, they are
counter-intuitive:

1. **The script text is inlined by command substitution**, so `| tee log.txt`
   attaches to the script's *last line* only — `(return 2> /dev/null) || main`
   becomes `... || main | tee log.txt`. `return` fails when not sourced, so
   `main` runs: the **interactive menu**, not `auto()` directly.
2. **`-o pipefail` makes the exit status truthful, and must stay.** Without it
   the pipeline reports `tee`'s status — `0` even when the script aborted a
   third of the way in. It adds no abort points inside the scripts (every
   pipeline there has a first stage that cannot fail on its own).
3. **Driving the menu from stdin needs a trailing `q`.** Feed
   `printf '1\nn\nq\n'`: `1` runs `auto()`, `n` answers `ask_reboot`, `q`
   exits. Without the `q`, `read` hits EOF, `choice` stays empty, the `case`
   falls to `*` and the menu **loops forever** printing `[!] Wrong input!`.

### Testing under `-e`: two runs, a fresh container each

errexit is live inside `main`/`auto()`, which is right on real hardware but
makes container coverage impossible: the systemd/D-Bus calls fail for
environmental reasons and stop the run early. So use two runs, each in its own
new container (contract point 4):

- **Faithful run** — the exact README line, `-e` included. Tells you what a
  user really gets, and where it stops.
- **Coverage run** — same command with `-e` dropped, purely as a testing
  device so execution continues past container-only failures and the later
  functions get exercised. Never propose this as a change to the README.

`msg()` runs `tput` before every step, and `tput` fails when `TERM` is unset or
`dumb` — so under `-e` an unprimed container dies at the first banner having
done nothing. Prime it (step 2). The same applies on real hardware under
`cron`, a non-TTY SSH session, or a `sudo` that drops `TERM`: worth reporting
if you see it.

## Procedure

1. **Record which images already exist, before pulling anything** — cleanup in
   step 6 must not delete an image the user already had:
   ```bash
   podman images --format '{{.Repository}}:{{.Tag}}' | grep -iE 'fedora|debian|<distro>'
   ```
   Then take the base image from the table above.

   (`podman` is assumed throughout; `docker` on this host is an alias for it.)
   Budget ~3 GB of pulls/installs per full run — cursor and code are ~1 GB
   each installed, plus claude-code, qemu/libvirt and ffmpeg.

2. **Start a disposable container** and copy the script in. **One container
   per run** — give each its own name so a used one is never reused (e.g.
   `<distro>-faithful` and `<distro>-coverage`); `<distro>-test` below is a
   placeholder for whichever run you are setting up:
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
   `DONE_EXIT:` is meaningful under `-e -o pipefail`: nonzero means the run
   aborted, and step 4 tells you where. (Exception: the coverage run drops
   `-e`, so there the value is just the last command's status and means
   nothing.)

   **Isolated function runs are a debugging aid, never the test** — the
   contract is a whole run from clean. Later functions also rely on state
   earlier ones leave behind: `setup_fonts` and `install_veracrypt` call
   `wget` without installing it, because `install_packages` already did, so a
   standalone run reports a false `wget: command not found`. To try one
   anyway, **source** the script (which makes the trailing `return` succeed so
   the menu never fires) and treat the result as a rough signal:
   ```bash
   podman exec <distro>-test bash -c "source /root/<script>.sh; setup_tlp"
   ```

4. **Read the outcome — the banner sequence is the primary signal.** Fail-fast
   makes this simple: compare the step banners that ran against the
   `msg '...'` calls in `auto()`. `msg()` wraps them in colour codes when
   `TERM`/`ncurses` are present, so a plain `grep '^\[\*\]'` finds **nothing**
   — strip the escapes:
   ```bash
   podman cp <distro>-test:/root/run.log ./
   grep -aoE '\[\*\] .*' run.log | sed 's/\x1b\[[0-9;]*m//g'
   grep -oE "msg '.*'" <script>.sh     # the expected sequence
   ```
   Reaching `[*] Done!` means **every command in every function returned 0** —
   `-e` guarantees it, so there is no silent failure left to hunt for.
   Stopping short means `-e` aborted there, and **the last banner names the
   failing function**; nothing after it ran. On a faithful container run
   expect a stop at `[*] Setting up firewall` (the `systemctl` calls) —
   environmental, not a script bug.

   Log-scraping is only needed for the **coverage** run, which deliberately
   continues past failures:
   ```bash
   grep -inE "error|fail|not found|no such|unable|cannot|denied|does not exist" run.log
   ```
   Sort hits against "Expected non-bugs" below plus the distro reference's own
   noise list.

5. **Verify a fix achieved its intent, not merely that it ran.** `-e` proves
   commands returned 0; it cannot prove they did what you meant — `dnf remove
   firefox` returns 0 when firefox was never installed. So after a fix, query
   state directly (exact commands in the distro reference):
   ```bash
   podman exec <c> <query-installed> <pkg>
   podman exec <c> flatpak list
   ```
   This is what proved `tlp` installed with `tuned`/`tuned-ppd` gone, and that
   apt had auto-removed `power-profiles-daemon`.

6. **Clean up unconditionally.** Containers first (force-remove; they are
   still "running" on `sleep infinity`), then only those images step 1 showed
   were absent beforehand:
   ```bash
   podman rm -f <distro>-test
   podman rmi <image>   # ONLY if step 1 showed it was not already present
   ```
   A `SIGTERM failed to stop container ... resorting to SIGKILL` warning here
   is expected and harmless. Removing a tag that shares an image ID with
   another tag (e.g. `debian:13` vs `debian:trixie`) only untags it.

7. **Report the outcome**, then offer the full log rather than pasting it —
   these run to several thousand lines. Say where the run stopped and why:
   completed, halted for a container-only reason, or halted on a real bug.
   Ask before dumping the log.

## Expected non-bugs (container artifacts)

Distro-agnostic; the distro reference lists its own additions. Under `-e` any
of these **halts the faithful run** — that is the environment failing, not the
script, and it is exactly why the coverage run exists. Don't report them as
findings:
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

Fixed instances live in each distro reference. Two things worth carrying:

- **A fix does not port across package managers.** Installing `tlp` before
  removing what it conflicts with is fatal under `dnf`, which aborts the whole
  transaction, but harmless under `apt`, which auto-removes the conflict and
  completes. Reproduce the failure on *that* distro before "fixing" it —
  assuming the Fedora bug existed on Debian too would have changed working
  code for nothing.
- **Still open: unguarded globs.**
  `for userpath in /home/*; do usermod -a -G libvirt,kvm $(basename $userpath); done`
  — with no match the glob stays literal and `usermod` fails with
  `user '*' does not exist`. A real desktop has a home directory so it rarely
  fires, but under `-e` it is fatal wherever it does, killing the run at
  `install_qemu`. Guard with `shopt -s nullglob` or a `[ -d ... ]` test.

## Adding a new distro

1. Copy `.claude/skills/test-setup-script/references/_template.md` to
   `.claude/skills/test-setup-script/references/<distro>.md` and fill it in.
2. Add a row to the table at the top of this file.
3. **Check the script actually follows the shared skeleton** before trusting
   this procedure on it: it needs `main` → menu → `auto()`, `msg()`,
   `ask_reboot`, and the trailing `(return 2> /dev/null) || main`. If it
   diverges, the whole "How the README invokes these" section may not apply —
   re-derive it rather than assuming.
4. **Check the distro is testable this way at all.** An image-based or atomic
   distro (`rpm-ostree`, `transactional-update`) does not install packages
   into a running container the way `dnf`/`apt` do, so a container run would
   prove nothing. Say so rather than reporting a green run.
5. Confirm the base image's init situation as in step 2 (no systemd → use
   `sleep infinity`).
