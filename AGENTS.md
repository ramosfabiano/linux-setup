# Agent instructions

Personal post-install setup scripts. Humans use [README.md](README.md).

## Scripts

| Distro | File |
|---|---|
| Debian 13 | `debian-13-setup.sh` |
| Fedora 44 | `fedora-44-setup.sh` |

Root-only, function-based bash. Each package step is a function; `auto()` runs them in a fixed order. File-scope `set -e` and `set -o pipefail` enforce the contract below. The last line is `(return 2> /dev/null) || main`, so a wget-inlined run starts the interactive menu, not `auto()` directly.

## Contract

1. If **any** command in **any** function fails, the whole run has failed. Execution stops; nothing after it runs.
2. There is no recovery and no resuming. A failed run is simply over.
3. The scripts are **not** idempotent. They assume a clean starting state and may only be run once against it.
4. Every run — real or test — starts from a **fresh** machine or container. To run again, throw the environment away and start over.

Do not remove `set -e` to finish a half-run, and do not add idempotency guards because a second run would duplicate something. A truncated log is the design working; the step it stopped at is the finding.

## Testing

When asked to test a `<distro>-NN-setup.sh` script, **read and follow** [`.claude/skills/test-setup-script/SKILL.md`](.claude/skills/test-setup-script/SKILL.md) (same text lives at [`.cursor/rules/test-setup-script.mdc`](.cursor/rules/test-setup-script.mdc)).

**Everything runs inside a disposable podman container — never on the host.** That includes the setup script, the generated test copy, and any check that demonstrates a failure mode. `systemctl` would hit the real system bus, `/proc/swaps` is not namespaced so `swapoff` sees host devices, and `mount -a` acts on the real fstab.

A container run with untestable functions stubbed is not full validation. Name every skipped function in the report.
