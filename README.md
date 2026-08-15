# Linux Setup

Post-install setup scripts for personal use.


## Debian 13

`sudo bash -c "$(wget -qO- https://raw.githubusercontent.com/ramosfabiano/linux-setup/main/debian-13-setup.sh) | tee log.txt"`


## Fedora 44

`sudo bash -e -c "$(wget -qO- https://raw.githubusercontent.com/ramosfabiano/linux-setup/main/fedora-44-setup.sh) | tee log.txt"`


## Testing changes

To test changes to one of these scripts, test it end-to-end in a
disposable container rather than on real hardware. The procedure is written up as a
shared skill/rule usable from both Claude Code and Cursor:
[.claude/skills/test-setup-script/SKILL.md](.claude/skills/test-setup-script/SKILL.md)
(symlinked at [.cursor/rules/test-setup-script.mdc](.cursor/rules/test-setup-script.mdc)).

