---
name: test-setup-script
description: Test one of this repo's distro post-install setup scripts (e.g. fedora-44-setup.sh, debian-13-setup.sh) end-to-end in a disposable container, verify fixes after editing them, and leave no leftover containers or images. Use when asked to test, verify, validate, or re-check a setup script, or after fixing a bug in one.
globs:
alwaysApply: false
---

# Testing a distro setup script in a container

These scripts are root-only, function-based bash: each `dnf`/`apt` step lives in
its own function, and `auto()` runs them in a fixed order. There's no `set -e`,
so one failing command doesn't stop the run — which means a script can "finish"
and print `Done!` while a step silently failed. Verifying it actually worked
requires running it and reading the output, not just reading the code.

Containers are close enough to bare metal for almost everything these scripts
do (dnf/apt installs, repo setup, flatpak, downloads + GPG verification). Only
systemd/D-Bus-dependent steps (`systemctl`, `firewall-cmd`) can't be fully
exercised — see "Expected non-bugs" below.

## Procedure

1. **Pick the matching base image** for the script's distro/version, e.g.:
   - `fedora-NN-setup.sh` → `registry.fedoraproject.org/fedora:NN`
   - `debian-NN-setup.sh` → `docker.io/library/debian:NN`

2. **Start a disposable container** and copy the script in:
   ```bash
   podman run -d --name <distro>-test <image> sleep infinity
   podman cp <script>.sh <distro>-test:/root/<script>.sh
   podman exec <distro>-test chmod +x /root/<script>.sh
   ```
   Use `sleep infinity` as the command, not the distro's default init. These
   base images don't ship systemd at all (`rpm -q systemd` / `dpkg -l systemd`
   comes back empty), so there's no real PID 1 to boot — trying to run
   `/sbin/init` just fails to start. Accept that `systemctl`/`firewall-cmd`
   calls will hit "no systemd/D-Bus" errors and treat that as an environment
   limit, not a test blocker (see below).

3. **Run functions by sourcing, not executing.** The script's last line is
   `(return 2> /dev/null) || main` — sourcing it makes `return` succeed, so
   `main()` (the interactive menu) never fires. This lets you call individual
   functions or `auto()` directly:
   ```bash
   podman exec <distro>-test bash -c "source /root/<script>.sh; auto"
   ```

4. **Test the whole `auto()` sequence in order, not functions in isolation.**
   Later functions depend on state earlier ones leave behind — e.g.
   `setup_fonts`/`install_veracrypt` call `wget` but don't install it
   themselves, because `install_packages` (run earlier in `auto()`) already
   did. Testing a later function standalone in a fresh container produces a
   false "wget: command not found" that isn't a real bug in the intended
   flow. When you do need to isolate one function (e.g. to verify a targeted
   fix), reproduce the same ordering/state it would normally have, or accept
   the isolated result only as a rough signal.

5. **Run the full sequence in the background and poll for completion** — a
   full `auto()` run installs a lot of packages and can take 10-15 minutes:
   ```bash
   podman exec -d <distro>-test bash -c \
     "source /root/<script>.sh; auto > /root/auto.log 2>&1; echo EXIT:\$? >> /root/auto.log"
   ```
   Then wait (e.g. `until podman exec <distro>-test grep -q '^EXIT:' /root/auto.log; do sleep 5; done`,
   run via a backgrounded Bash call) instead of blocking the whole session on it.

6. **Pull the log and triage.** Copy it out (`podman cp <distro>-test:/root/auto.log ./`)
   and grep broadly, then read context around every hit — the grep is a
   starting point, not a verdict:
   ```bash
   grep -inE "error|fail|not found|no such|unable|cannot|denied|not installed|does not exist" auto.log
   ```
   Sort each hit into "expected container limitation" (below) or "real bug."

7. **After fixing a real bug, re-verify in a *fresh* container**, not the one
   that already ran the broken version — leftover package/repo state can mask
   a fix that doesn't actually work from a clean system. Re-run just the
   affected function(s) and confirm the specific failure signature is gone.

8. **Clean up everything you created, unconditionally** — containers first
   (force-remove, they may still be "running" on `sleep infinity`), then any
   image you pulled specifically for this test. Leave pre-existing
   images/containers on the host untouched:
   ```bash
   podman rm -f <distro>-test
   podman rmi <image>   # only if you pulled it for this test
   ```

## Expected non-bugs (container artifacts, not script bugs)

Don't report these as findings — they're artifacts of testing in a
container, not something a real install would hit:
- `systemctl ...` / `firewall-cmd ...` → `System has not been booted with
  systemd as init system` / `Failed to connect to system scope bus` / `Failed
  to connect to socket /run/dbus/system_bus_socket`. No systemd/D-Bus PID 1
  in the container.
- `flatpak install` → `bwrap: Creating new namespace failed: Operation not
  permitted`. Nested user-namespace sandboxing is restricted inside the
  container; the flatpak still installs.
- `tput: command not found`, `xset: unable to open display`. Minimal images
  lack ncurses-utils/X; irrelevant on a real desktop.
- `Failed to connect to audit log, ignoring` during rpm/dpkg scriptlets. No
  kernel audit subsystem visible in the container.
- A function reading `sudo` while running as root: harmless as long as
  `sudo` is installed (check `rpm -q sudo`/`dpkg -l sudo` if it errors).

## Real bug patterns actually found this way

Keep an eye out for these shapes of bug — they reproduce identically on real
hardware, so they're always worth fixing:
- **Install-before-remove ordering against a package manager conflict.**
  E.g. installing `tlp` before removing the package(s) it conflicts with
  (`tuned`/`tuned-ppd`/`power-profiles-daemon`, present by default on a
  Fedora/GNOME desktop install). **Verify per distro/package-manager** — don't
  assume the same fix pattern applies everywhere: `dnf` hard-aborts the whole
  transaction on a conflict, while `apt` on Debian resolved the equivalent
  `tlp` vs `power-profiles-daemon` conflict by auto-removing the conflicting
  package and completing the install. Confirm the actual behavior in a
  container before "fixing" something that isn't broken on that distro.
- **Reused config/repo identifiers across unrelated integrations.** E.g. two
  separate `dnf` repo files (`cursor.repo`, `vscode.repo`) both declaring
  `[code]` as the repo id — undefined/fragile even when it happens to still
  install successfully; give each a unique id.
- **Unguarded shell globs that don't expand when empty.** E.g.
  `for userpath in /home/*; do usermod -a -G libvirt,kvm $(basename $userpath); done`
  — with no matching directory, the glob stays literal, `basename` returns
  `*`, and `usermod` fails with `user '*' does not exist`. Guard with
  `shopt -s nullglob` or a `[ -d "$userpath" ]` check.
