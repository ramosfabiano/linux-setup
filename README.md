# Linux Setup

Automated post-install scripts for personal use.

These scripts should be run right after a fresh install.

*Note that these scripts are NOT idempotent.*

## Ubuntu 24.04.02 LTS.

`sudo bash -c "$(wget -qO- https://raw.githubusercontent.com/ramosfabiano/linux-setup/main/ubuntu-2404-setup.sh) | tee log.txt"`


## Fedora 42.

`sudo bash -e -c "$(wget -qO- https://raw.githubusercontent.com/ramosfabiano/linux-setup/main/fedora-42-setup.sh) | tee log.txt"`
