# Linux Setup

Post-install setup scripts for personal use.


## Debian 13

`sudo bash -c "$(wget -qO- https://raw.githubusercontent.com/ramosfabiano/linux-setup/main/debian-13-setup.sh) | tee log.txt"`


## Fedora 44

`sudo bash -e -c "$(wget -qO- https://raw.githubusercontent.com/ramosfabiano/linux-setup/main/fedora-44-setup.sh) | tee log.txt"`


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

