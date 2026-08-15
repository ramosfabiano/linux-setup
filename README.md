# Linux Setup

Post-install setup scripts for personal use.

These run fail-fast: the scripts set `-e` and `-o pipefail`, so if
any command in any function fails, the run is over — it does not continue,
recover or resume, and it exits nonzero. 

Thus, the scripts are **not idempotent**
and are meant to be run **once** against a freshly installed system.
Re-running them on a machine they have already touched is not supported; if a
run fails, fix the cause and start again from a clean install.


## Debian 13

`sudo bash -c "$(wget -qO- https://raw.githubusercontent.com/ramosfabiano/linux-setup/main/debian-13-setup.sh)"`


## Fedora 44

`sudo bash -c "$(wget -qO- https://raw.githubusercontent.com/ramosfabiano/linux-setup/main/fedora-44-setup.sh)"`


## Testing changes

To partially test changes to one of these scripts, test it end-to-end in a
disposable container rather than on real hardware. The procedure is written up as a
shared skill/rule usable from both Claude Code and Cursor.

**Claude Code**: picked up automatically — just ask it
to test or verify a setup script and it will
apply the procedure. No manual invocation needed.

**Cursor**: the agent decides whether to pull it in based on its description
when your prompt is about testing one of these scripts, and can
also be referenced explicitly in a prompt with `@test-setup-script`.

Keep in mind that some of
the script's functions cannot be tested in a container. Functions that cannot
work there (zram, firewall, TLP, …) are skipped entirely. 
A real machine or a full VM is the only complete test.
