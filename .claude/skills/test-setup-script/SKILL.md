---
name: test-setup-script
description: Test one of this repo's distro post-install setup scripts (<distro>-NN-setup.sh) end-to-end in a disposable podman container.
globs:
alwaysApply: false
---
# Testing a distro setup script in a container

One run, exactly as the README invokes it. No variant runs, no relaxed modes.
Only package-manager details differ per distro; the table below has them.

> **Everything runs inside the container — never on the host.** That means the
> setup script, the generated test copy, and *any* check that demonstrates a
> failure mode.
> Never execute the script or a fragment of it directly on the host: `systemctl`
> would hit the real system bus, `/proc/swaps` is not namespaced so `swapoff`
> sees host devices, and `mount -a` acts on the real fstab. If you need a
> control case — "show that it dies without the skips" — run it in a second
> throwaway container, not in your shell.

| Distro | Script | Base image | Pkg mgr | Query installed | `tput` needs |
|---|---|---|---|---|---|
| Fedora | `fedora-NN-setup.sh` | `registry.fedoraproject.org/fedora:NN` | `dnf` | `rpm -q <pkg>` | `dnf -y install ncurses` |
| Debian | `debian-NN-setup.sh` | `docker.io/library/debian:NN` | `apt` | `dpkg -l <pkg>` | `apt-get install -y ncurses-bin` |


## The contract

1. If **any** command in **any** function fails, the whole run has failed.
   Execution stops there; nothing after it runs.
2. There is no recovery and no resuming. A failed run is simply over.
3. The scripts are **not** idempotent and are not meant to be. They assume a
   clean starting state and may only be run once against it.
4. Therefore every run — real or test — starts from a **fresh** machine or
   container. To run again, throw the environment away and start over.

Do not "fix" a half-finished run by removing `set -e`, and do not add idempotency
guards on the grounds that a second run would duplicate something: a second
run is not a supported flow. A truncated log is the design working, and the
step it stopped at is the finding.

## The run

The scripts are root-only, function-based bash: each package step is a
function, and `auto()` runs them in a fixed order. **Each script sets `set -e`
and `set -o pipefail` at file scope**, so the contract is enforced however the
script is started — the README line adds nothing:

```bash
sudo bash -c "$(wget -qO- .../<distro>-setup.sh)"
```

Consider these, as they are counter-intuitive:

1. **The script text is inlined by command substitution**, so what actually
   executes is the file's last line, `(return 2> /dev/null) || main`. `return`
   fails when not sourced, so `main` runs: the **interactive menu**, not
   `auto()` directly.
2. **Driving the menu from stdin needs a trailing `q`.** Feed
   `printf '1\nn\nq\n'`: `1` runs `auto()`, `n` answers `ask_reboot`, `q`
   exits. Without the `q`, `read` hits EOF, `choice` stays empty, the `case`
   falls to `*` and the menu prints `[!] Wrong input!` — under `set -e` the
   failing `read` then ends the run, but supply the `q` and be explicit.

## Skipping what a container cannot run

Some functions contain commands that cannot work in a container for reasons
that have nothing to do with the script. Under `set -e` the first one ends the run
— on Debian, for instance, that is `systemctl` in `setup_zram`, **step 1 of 14**.
Keep an eye on other cases that may appear eventually.

**A function is either executed in full or skipped in full. Never partially.**
Do not stub individual commands inside an otherwise-running function: the
function would then report success having performed only some of its work,
which is a result you cannot reason about.

Derive the skip list from the script itself — do not keep one written down,
it goes stale the moment a function gains a new call. Then build a test copy
with those functions reduced to `:` and run the README invocation against it:

```bash
# commands that cannot work in a container; this list IS the criterion
UNTESTABLE='systemctl|firewall-cmd|ufw |virsh|modprobe|setenforce|swapoff|swapon|mount -a|locale-gen|tlp-stat|dmesg|/etc/selinux'

skip=$(awk -v pat="$UNTESTABLE" '
  /^[a-z_]+\(\) \{/ { fn=$1; sub(/\(\)/,"",fn); hit=0 }
  fn && $0 !~ /^[ \t]*#/ && $0 ~ pat { hit=1 }
  /^\}/ { if (fn && hit) print fn; fn="" }
' <script>.sh | tr '\n' ' ')
echo "skipping: $skip"

awk -v skip="$skip" '
  BEGIN { n=split(skip,a," "); for(i=1;i<=n;i++) s[a[i]]=1 }
  /^[a-z_]+\(\) \{/ {
    fn=$1; sub(/\(\)/,"",fn)
    if (fn in s) { print fn"() {"; print "    : # SKIPPED: cannot run in a container"; print "}"; inskip=1; next }
  }
  inskip && /^\}/ { inskip=0; next }
  !inskip
' <script>.sh > <script>-test.sh
```

Verify the copy before using it: `bash -n` must pass, and its function list
must match the original — only the bodies change.

`swapoff`/`swapon` are in that list for safety, not just fidelity:
**`/proc/swaps` is not namespaced**, so a container reads the *host's* swap
table and could act on host devices. If a run dies on some other
container-only impossibility, add that command to `UNTESTABLE` above and tell
the user the skill needs it.

**What this costs, and it is not small:** everything inside a skipped function
goes untested, including package work a container could otherwise verify.
`setup_tlp` is skipped on both distros, so the `tuned`/`tlp` conflict — the
most serious bug ever found in these scripts — is **no longer covered by this
test**. A throwaway VM is the only way to validate the skipped functions.
That is why step 7 requires naming them in every report.

## Procedure

1. **Record which images already exist, before pulling anything** — cleanup in
   step 6 must not delete an image the user already had:
   ```bash
   podman images --format '{{.Repository}}:{{.Tag}}' | grep -iE 'fedora|debian|<distro>'
   ```
   Then take the base image from the table above. (`podman` is assumed;
   `docker` on this host is an alias for it.) Budget ~3 GB per run.

2. **Start a fresh container** and copy in the *generated test copy*, not the
   original:
   ```bash
   podman run -d --name <distro>-test <image> sleep infinity
   podman cp <script>-test.sh <distro>-test:/root/<script>.sh
   ```
   Install the `tput` package from the table above and export `TERM=xterm`,
   or `msg()`'s `tput` fails and `set -e` kills the run at the first banner.

   Use `sleep infinity`, not the distro's init: neither base image ships
   systemd (`rpm -q systemd` → *not installed*; `dpkg -l systemd` → *no
   packages found*), so there is no PID 1 to boot.

3. **Run it, exactly as the README does.** Using the local copy via `cat` is
   equivalent to `wget -qO-` — both inline the script text — and tests your
   uncommitted edits:
   ```bash
   podman exec -d <distro>-test bash -c \
     'export TERM=xterm
      printf "1\nn\nq\n" | bash -c "$(cat /root/<script>.sh)" \
        > /root/run.log 2>&1; printf "\nDONE_EXIT:%s\n" "$?" >> /root/run.log'
   ```
   The redirect to `run.log` is the harness capturing output for triage — it
   is not part of the README invocation, which no longer logs anything. Write
   the marker with a leading newline: the script's last output may end without
   one, and `DONE_EXIT` glued onto a partial line defeats the `^` anchor below
   and the watchdog then waits forever.

   A full run takes several minutes, so launch it detached and watch it from a
   backgrounded Bash call rather than blocking the session. **Watch for stalls,
   not just completion** — a run can block indefinitely on an interactive
   prompt, and a plain `until` loop would poll forever:

   ```bash
   watch_run() {   # $1=container  [$2=stall secs, default 180]  [$3=cap secs, default 1800]
     local c=$1 stall=${2:-180} cap=${3:-1800}
     local last=-1 quiet=0 waited=0 poll=20 n
     while :; do
       if podman exec "$c" grep -q '^DONE_EXIT:' /root/run.log 2>/dev/null; then
         echo "FINISHED $(podman exec "$c" sh -c 'tail -1 /root/run.log')"; return 0
       fi
       n=$(podman exec "$c" sh -c 'wc -c < /root/run.log' 2>/dev/null || echo 0)
       if [ "$n" = "$last" ]; then quiet=$((quiet+poll)); else quiet=0; last=$n; fi
       if [ "$quiet" -ge "$stall" ]; then echo "STALLED: no output for ${quiet}s (log $n bytes)"; return 1; fi
       waited=$((waited+poll))
       if [ "$waited" -ge "$cap" ]; then echo "TIMEOUT: ${waited}s elapsed, still running"; return 2; fi
       sleep "$poll"
     done
   }
   watch_run <distro>-test
   ```
   It measures **bytes**, not lines, so a progress bar redrawing one line with
   `\r` still counts as alive — verified against both a real stall and a slow
   healthy run. Three minutes of total silence means stuck; 30 minutes total is
   the backstop. `DONE_EXIT:` is the script's own exit status: nonzero means
   the run aborted.

   **If it reports STALLED**, get the cause before killing anything — the
   process tree names it immediately:
   ```bash
   podman exec <c> sh -c 'ps -eo pid,stat,args' | grep -iE 'debconf|whiptail|dialog|apt|dpkg|dnf|wget|curl'
   podman exec <c> sh -c "grep -aoE '\[\*\] .*' /root/run.log | tail -1"   # step it died in
   podman exec <c> sh -c 'tail -5 /root/run.log' | cat -v                    # escape codes made visible
   ```
   The usual cause is an interactive prompt with no one to answer it. A run
   once hung on `python-sympy-doc`'s debconf dialog, reachable only because a
   large dependency tree had installed `whiptail`, which switches debconf to
   the blocking dialog frontend. The Debian script now exports
   `DEBIAN_FRONTEND=noninteractive` to prevent it; Fedora needs no equivalent,
   `dnf` has no debconf.

4. **Read the outcome — the banner sequence is the primary signal.** Compare
   the banners that ran against the `msg '...'` calls in `auto()`; `msg()`
   wraps them in colour codes, so strip the escapes:
   ```bash
   podman cp <distro>-test:/root/run.log ./
   grep -aoE '\[\*\] .*' run.log | sed 's/\x1b\[[0-9;]*m//g'
   grep -oE "msg '.*'" <script>.sh     # the expected sequence
   ```
   With the skipped functions reduced to `:` the run **should reach
   `[*] Done!`**, and reaching it means every command in every function
   returned 0. Stopping short is a real finding: the last banner names the
   failing function, and nothing after it ran. If the cause is another
   container-only impossibility, add it to `UNTESTABLE` — then say so.

5. **Verify a fix achieved its intent, not merely that it ran.** `-e` proves
   commands returned 0, not that they did what you meant — `dnf remove
   firefox` returns 0 when firefox was never installed:
   ```bash
   podman exec <c> <query-installed> <pkg>
   podman exec <c> flatpak list
   ```

6. **Clean up unconditionally.** Containers first (force-remove; they are
   still "running" on `sleep infinity`), then only images step 1 showed were
   absent beforehand:
   ```bash
   podman rm -f <distro>-test
   podman rmi <image>   # ONLY if step 1 showed it was not already present
   ```

7. **Report — and always disclose what was neutralised.** State where the run
   stopped (completed, or the function it died in), then **name every skipped
   function and say it was not tested**:
   ```bash
   grep -B1 'SKIPPED: cannot run in a container' <script>-test.sh | grep '()'
   ```
   The summary must make clear which operations were **not** tested, so a
   green run is never mistaken for full validation. Offer the full log rather
   than pasting it — these run to several thousand lines.

## Expected non-bugs (container artifacts)

With the untestable functions skipped, most environmental noise is gone.
What remains:
- `xset: unable to open display`, `Failed to connect to audit log, ignoring`.
  Minimal image, no X, no audit subsystem.

## What a container cannot tell you

The skipped functions are the hardware-facing ones, so nothing they do is
tested — not even their package installs. Of what still runs, the intel media
drivers install cleanly but prove nothing about the hardware. And because the
container shares the host's `/proc` and `/sys`, any hardware-facing output can
look convincingly real while describing the **host**.

Locale-dependent failures are invisible here too: a container carries one
langpack (`glibc-minimal-langpack`) where a real desktop install carries a
full set. Fedora's `*-langpack-*` subpackages pin their base package to an
exact version, so a plain `dnf update` can break the transaction on a real
machine in a way no container run will ever reproduce.

## Real bug patterns

- **A fix does not port across package managers.** Installing `tlp` before
  removing what it conflicts with is fatal under `dnf`, which aborts the whole
  transaction, but harmless under `apt`, which auto-removes the conflict and
  completes. Reproduce the failure on *that* distro before "fixing" it —
  assuming the Fedora bug existed on Debian too would have changed working
  code for nothing.
