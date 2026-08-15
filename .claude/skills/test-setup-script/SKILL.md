---
name: test-setup-script
description: Test one of this repo's distro post-install setup scripts (fedora-44-setup.sh, debian-13-setup.sh) end-to-end in a disposable podman container, verify a fix after editing one, and clean up leaving no leftover containers or images. Use when asked to test, verify, validate, re-check or reproduce a bug in a setup script, or right after changing one.
globs:
alwaysApply: false
---
# Testing a distro setup script in a container

These scripts are root-only, function-based bash: each `dnf`/`apt` step lives in
its own function, and `auto()` runs them in a fixed order. Neither script sets
`set -e` internally, so how failures behave depends entirely on how the script
is *invoked*. Read "How the README actually invokes these" before interpreting
any result.

Containers are close enough to bare metal for package-manager work (dnf/apt
installs, repo setup, flatpak, downloads + GPG verification). Two categories
can't be judged from a container at all: systemd/D-Bus steps, and anything
hardware-dependent — see "Expected non-bugs" and "What a container cannot tell
you".

## How the README actually invokes these

Test the script the way it will really be run. The README lines are:

```bash
sudo bash -c "$(wget -qO- .../<distro>-setup.sh) | tee log.txt"
```

Both distros use this same form. Three consequences, all verified empirically
— do not assume, they are counter-intuitive:

1. **The script text is inlined by command substitution**, so `| tee log.txt`
   attaches to the script's *last line* only — `(return 2> /dev/null) || main`
   becomes `... || main | tee log.txt`. `return` fails when not sourced, so
   `main` runs: the **interactive menu**, not `auto()` directly.
2. **`tee` masks the exit code**, so the run's status tells you nothing: the
   pipeline reports `tee`'s status, which is `0` even when the script failed.
   Judge a run by its log, never by `$?`.
3. **Driving the menu from stdin needs a trailing `q`.** Feed
   `printf '1\nn\nq\n'`: `1` runs `auto()`, `n` answers `ask_reboot`, `q`
   exits. Without the `q`, `read` hits EOF, `choice` stays empty, the `case`
   falls to `*` and the menu **loops forever** printing `[!] Wrong input!`.

**Do not add `-e` to these invocations, and treat its reappearance as a bug.**
The Fedora line used to read `bash -e -c`, which was measurably harmful:
errexit is live inside `main`/`auto()`, so the first command returning nonzero
aborted everything after it while consequence 2 still reported success. With
`ncurses` present the run died at `setup_firewall`'s `systemctl disable sshd`
and silently skipped the last six steps, exiting `0`; in a bare container it
died even earlier, on `msg()`'s own `tput setaf 2`, installing *nothing* and
still exiting `0`. `msg()` runs before every step, so under `-e` it is a
recurring tripwire — and `tput` also fails with `No value for $TERM` whenever
`TERM` is unset, as under a bare `sudo`, cron, or a non-TTY SSH session.

## Procedure

1. **Record which images already exist, before pulling anything** — cleanup in
   step 8 must not delete an image the user already had:
   ```bash
   podman images --format '{{.Repository}}:{{.Tag}}' | grep -iE 'fedora|debian'
   ```
   Then pick the matching base image:
   - `fedora-NN-setup.sh` → `registry.fedoraproject.org/fedora:NN`
   - `debian-NN-setup.sh` → `docker.io/library/debian:NN`

   (`podman` is assumed throughout; `docker` on this host is an alias for it.)
   Budget ~3 GB of pulls/installs per full run — cursor and code are ~1 GB
   each installed, plus claude-code, qemu/libvirt and ffmpeg.

2. **Start a disposable container** and copy the script in:
   ```bash
   podman run -d --name <distro>-test <image> sleep infinity
   podman cp <script>.sh <distro>-test:/root/<script>.sh
   ```
   Optionally `dnf -y install ncurses` and export `TERM=xterm` so `msg()`'s
   `tput` works and the step banners render as they would on a real desktop;
   without it every `msg()` logs a harmless `tput: command not found`.
   Use `sleep infinity`, not the distro's init. Verified: neither base image
   ships systemd (`rpm -q systemd` → *not installed*; `dpkg -l systemd` → *no
   packages found*), and neither has `/sbin/init` or
   `/usr/lib/systemd/systemd`, so there is no PID 1 to boot and
   `--systemd=always` buys nothing.

3. **Run it the README way** (see above). Using the local working copy via
   `cat` is equivalent to the README's `wget -qO-` — both just inline the
   script text — and tests your uncommitted edits:
   ```bash
   podman exec -d <distro>-test bash -c \
     'printf "1\nn\nq\n" | bash -c "$(cat /root/<script>.sh) | tee /root/log.txt" \
        > /root/run.log 2>&1; echo "DONE_EXIT:$?" >> /root/run.log'
   ```
   A full run takes 10-15 minutes, so launch it detached (`exec -d`) and poll
   for the marker from a backgrounded Bash call rather than blocking the
   session:
   ```bash
   until podman exec <distro>-test grep -q '^DONE_EXIT:' /root/run.log; do sleep 10; done
   ```
   `DONE_EXIT:` is only a **completion sentinel — never a pass/fail signal.**
   `tee` masks the real status, and the value is otherwise just the last
   command's status: a healthy run once ended `EXIT:127` purely because
   `tlp-stat` was the final command and was missing.

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
   Known noise to skip: the package name `perl-Error`, and dozens of `Failed
   to connect to audit log, ignoring` lines from rpm scriptlets. Sort every
   remaining hit into "expected container artifact" (below) or "real bug".

   **Always confirm the run reached the end**, rather than assuming it did —
   compare the step banners that actually ran against the `msg '...'` calls in
   `auto()`. When `TERM`/`ncurses` are present `msg()` wraps them in colour
   codes, so a plain `grep '^\[\*\]'` finds **nothing** — strip the escapes:
   ```bash
   grep -aoE '\[\*\] .*' run.log | sed 's/\x1b\[[0-9;]*m//g'
   grep -oE "msg '.*'" <script>.sh     # the expected sequence
   ```
   A healthy full run ends with `[*] Done!` after all twelve steps. Anything
   short of that is truncation — which, given consequence 2, will still have
   exited `0`. This check is what caught the old `-e` invocation stopping at
   `[*] Setting up firewall` and skipping the last six steps.

6. **Confirm successes positively — absence of grep hits is weak evidence.**
   The decisive checks are direct queries:
   ```bash
   podman exec <c> rpm -q <pkg>          # or: dpkg -l <pkg>
   podman exec <c> flatpak list
   podman exec <c> cat /etc/yum.repos.d/<name>.repo
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

Don't report these as findings:
- `systemctl` / `firewall-cmd` → `System has not been booted with systemd as
  init system`, `Failed to connect to system scope bus`, `Failed to connect to
  socket /run/dbus/system_bus_socket`. No systemd/D-Bus PID 1.
- `flatpak install` → `bwrap: Creating new namespace failed: Operation not
  permitted`. Nested sandboxing is restricted; the flatpak still installs
  (confirm with `flatpak list`).
- `sed: can't read /etc/selinux/config` and `setenforce: SELinux is disabled`
  from `install_qemu` — no SELinux config in the image.
- `tput: command not found`, `xset: unable to open display`, `Failed to
  connect to audit log, ignoring`. Minimal image, no X, no audit subsystem.
- `Unit sshd.service does not exist` / `pcscd.service does not exist` — those
  packages aren't in a minimal image.
- `install_veracrypt` calling `sudo dnf` while already root: works (sudo is
  installed) but is a real inconsistency in the script, just a harmless one.

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

- **Install-before-remove against a package-manager conflict.** Installing
  `tlp` before removing what it conflicts with (`tuned`/`tuned-ppd`/
  `power-profiles-daemon`, present by default on a Fedora GNOME install).
  **Verify per package manager** — `dnf` hard-aborts the whole transaction,
  while `apt` on Debian resolved the same `tlp` vs `power-profiles-daemon`
  conflict by auto-removing the conflicting package and completing. Confirm in
  a container before "fixing" something that isn't broken on that distro.
- **Reused config/repo identifiers across unrelated integrations.** Two `dnf`
  repo files (`cursor.repo`, `vscode.repo`) both declaring `[code]` as the
  repo id — fragile even when it happens to still install. Give each a unique
  id.
- **Unguarded globs that don't expand when empty.**
  `for userpath in /home/*; do usermod -a -G libvirt,kvm $(basename $userpath); done`
  — with no match the glob stays literal and `usermod` fails with
  `user '*' does not exist`. Note this one is **latent on real hardware**
  (a desktop already has a home directory) and only surfaces in the empty
  container; still worth guarding with `shopt -s nullglob` or a `[ -d ... ]`
  test.
