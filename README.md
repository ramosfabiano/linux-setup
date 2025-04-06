# ubuntu-setup
  
An automated post-install script to set-up Ubuntu 24.04 LTS for my personal use.

Tested with Ubuntu 24.04.2.

#### Installation

This script is supposed to be run right after a fresh Ubuntu install.

You can download the script from the repo or use this one-liner command, there are no dependencies required.

`sudo bash -c "$(wget -qO- https://raw.githubusercontent.com/ramosfabiano/ubuntu-setup/main/ubuntu-setup.sh) | tee log.txt"`

After the install, reboot. *Note that this script is NOT idempotent.*