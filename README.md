# Linux Setup

Automated post-install scripts for personal use.

These scripts should be run right after a fresh install.

*Note that these scripts are NOT idempotent.*

## ubuntu-setup
  
Ubuntu 24.04.02 LTS.

#### Installation

`sudo bash -c "$(wget -qO- https://raw.githubusercontent.com/ramosfabiano/linux-setup/main/ubuntu-setup.sh) | tee log.txt"`


## fedora-setup
  
Fedora 42.

#### Installation

`sudo bash -e -c "$(wget -qO- https://raw.githubusercontent.com/ramosfabiano/linux-setup/main/fedora-setup.sh) | tee log.txt"`
