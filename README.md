# Linux Setup

Post-install setup scripts for personal use.

These run fail-fast (`-e`): if any command in any function fails, the run is
over — it does not continue, recover or resume. The scripts are **not
idempotent** and are meant to be run **once** against a freshly installed
system. Re-running them on a machine they have already touched is not
supported; if a run fails, fix the cause and start again from a clean install.


## Debian 13

`sudo bash -e -o pipefail -c "$(wget -qO- https://raw.githubusercontent.com/ramosfabiano/linux-setup/main/debian-13-setup.sh) | tee log.txt"`


## Fedora 44

`sudo bash -e -o pipefail -c "$(wget -qO- https://raw.githubusercontent.com/ramosfabiano/linux-setup/main/fedora-44-setup.sh) | tee log.txt"`


## Testing changes

To test changes to one of these scripts, test it end-to-end in a
disposable container rather than on real hardware. 
The procedure is written up as a
shared skill/rule usable from both Claude Code and Cursor.

**Claude Code**: picked up automatically — just ask it
to test or verify a setup script (or a fix you just made to one) and it will
apply the procedure. No manual invocation needed.

**Cursor**: the agent decides whether to pull it in based on its description
when your prompt is about testing/verifying one of these scripts. Can
also be referenced explicitly in a prompt with `@test-setup-script`.

Either way, requires `podman` (or `docker`) locally to spin up the
container.

The shared procedure lives in
[.claude/skills/test-setup-script/SKILL.md](.claude/skills/test-setup-script/SKILL.md),
with one small file per distro under
[.claude/skills/test-setup-script/references/](.claude/skills/test-setup-script/references/).
To cover a new distro, copy `references/_template.md`, fill it in and add a row
to the table at the top of `SKILL.md` — the procedure itself is not duplicated.

