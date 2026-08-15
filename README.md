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

