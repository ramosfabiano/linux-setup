#!/usr/bin/env bash

# Fail fast: any failing command ends the run. These scripts are not
# idempotent and are meant to be run once against a clean install; there
# is no recovery or resuming. pipefail covers the pipelines inside these
# functions (wget | gpg, echo | sha1sum --check), so a failing first stage is
# not hidden by a succeeding second one.
set -e
set -o pipefail

setup_zram() {
    # n/a on Fedora: zram swap is configured out of the box by zram-generator
    # (zram-generator-defaults), so there is nothing to set up here.
    :
}

setup_locale() {
    # n/a on Fedora: there is no /etc/locale.gen and no locale-gen binary;
    # locales ship as glibc-langpack-* packages and are chosen at install time.
    :
}

update_system() {
    # distro-sync, not update: langpack subpackages carry exact-version
    # dependencies on their base package (dnsmasq-langpack requires
    # dnsmasq = <version>, libreoffice-langpack-pt-BR requires
    # libreoffice-core = <version>). A plain update can move the base package
    # without its langpack and RPM then refuses the whole transaction.
    # distro-sync brings both to the repo version together; --refresh avoids
    # deciding on stale metadata.
    dnf -y --refresh distro-sync
}

install_external_repos() {
    dnf -y install https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm 
    dnf -y install https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm
    dnf -y --refresh distro-sync
}

setup_flatpak() {
    dnf -y install flatpak
    flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

    flatpak install flathub com.github.tchx84.Flatseal -y
    flatpak install flathub org.freeplane.App -y
    #flatpak install flathub md.obsidian.Obsidian -y
    flatpak install flathub org.mozilla.firefox -y
    flatpak install flathub org.mozilla.thunderbird_esr -y

    dnf remove  --noautoremove firefox -y
    dnf remove  --noautoremove thunderbird -y
}

install_packages() {
    # No thunderbird here: setup_flatpak installs the flatpak and removes the
    # rpm, so listing it meant downloading and installing ~360 MB purely to
    # delete it a step later.
    dnf -y install flatpak vim git \
        vlc cmake gcc-c++ boost-devel \
        dnsutils java-latest-openjdk astyle  \
        thermald curl wget liberation*fonts* \
        python3-pip pipx xsel firewall-config \
        hplip* cabextract lzip p7zip p7zip-plugins \
        gnome-tweaks gnome-shell-extension-common.noarch gnome-extensions-app \
        gnome-shell-extension-dash-to-dock gnome-shell-extension-appindicator \
        gdk-pixbuf2-modules-extra chromium solaar audacity gimp keepassxc \
        gnome-shell-extension-system-monitor

    dnf -y install faad2 flac lame libde265 x264 x265 --allowerasing
    dnf -y install ffmpeg-libs libva 
    dnf -y install libva-intel-media-driver intel-media-driver --allowerasing
    dnf -y install libva-intel-driver    
}

setup_podman() {
    dnf -y install podman podman-compose podman-docker 
}

setup_fonts() {
    dnf -y install curl cabextract xorg-x11-font-utils fontconfig
    wget https://downloads.sourceforge.net/project/mscorefonts2/rpms/msttcore-fonts-installer-2.6-1.noarch.rpm
    echo "0cd8fc72921f917ce27b2e639da6fe25eaa736b4  msttcore-fonts-installer-2.6-1.noarch.rpm" | sha1sum --check
    echo "55d7f3a86533225634ff3ea2384b4356d9665a29cc7eeacff16602a1714afbb4  msttcore-fonts-installer-2.6-1.noarch.rpm" | sha256sum --check
    rpm -i --nodigest msttcore-fonts-installer-2.6-1.noarch.rpm
    rm -f msttcore-fonts-installer-2.6-1.noarch.rpm
}

setup_firewall() {
    systemctl disable sshd
    firewall-cmd --set-default-zone public
    firewall-cmd --permanent --remove-service=ssh
    firewall-cmd --permanent --remove-service=dhcpv6-client
    firewall-cmd --permanent --remove-service=cockpit
    firewall-cmd --permanent --remove-service=mdns
    firewall-cmd --reload
    firewall-cmd --list-all
}

install_veracrypt() {
    export VC_VERSION="1.26.29"
    cd /tmp
    wget https://launchpad.net/veracrypt/trunk/$VC_VERSION/+download/veracrypt-$VC_VERSION-Fedora-44-x86_64.rpm
    wget https://launchpad.net/veracrypt/trunk/$VC_VERSION/+download/veracrypt-$VC_VERSION-Fedora-44-x86_64.rpm.sig
    wget https://www.idrix.fr/VeraCrypt/VeraCrypt_PGP_public_key.asc
    gpg --import VeraCrypt_PGP_public_key.asc
    gpg --verify veracrypt-$VC_VERSION-Fedora-44-x86_64.rpm.sig
    sudo dnf -y install ./veracrypt*.rpm
    rm -f VeraCrypt* veracrypt*  
}

install_cursor() {
    rpm --import https://downloads.cursor.com/keys/anysphere.asc
    echo '
[cursor]
name=Cursor
baseurl=https://downloads.cursor.com/yumrepo
enabled=1
gpgcheck=1
gpgkey=https://downloads.cursor.com/keys/anysphere.asc
' > /etc/yum.repos.d/cursor.repo
    dnf -y install cursor
}

install_vscode() {
    rpm --import https://packages.microsoft.com/keys/microsoft.asc
    echo '
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
' > /etc/yum.repos.d/vscode.repo
    dnf -y install code
}

install_claude() {
    rpm --import https://downloads.claude.ai/keys/claude-code.asc
    echo '
[claude-code]
name=Claude Code
baseurl=https://downloads.claude.ai/claude-code/rpm/stable
enabled=1
gpgcheck=1
gpgkey=https://downloads.claude.ai/keys/claude-code.asc
' > /etc/yum.repos.d/claude-code.repo
    dnf -y install claude-code
}

disable_smart_card() {
    for unit in pcscd.socket pcscd.service; do
        if systemctl cat "$unit" >/dev/null 2>&1; then
            systemctl disable --now "$unit"
            systemctl mask "$unit"
        fi
    done
}

install_qemu() {
    # still required?
    sed -i 's/^SELINUX=.*/SELINUX=permissive/' /etc/selinux/config
    setenforce 0

    dnf -y install bridge-utils libvirt virt-install qemu-kvm virt-viewer virt-manager spice-webdavd spice-gtk-tools swtpm.x86_64 edk2-ovmf  
    # Real login accounts. 1000-60000 is UID_MIN..UID_MAX from
    # /etc/login.defs, which excludes system accounts such as libvirt-qemu.
    for user in $(awk -F: '$3>=1000 && $3<=60000 {print $1}' /etc/passwd); do
        usermod -a -G libvirt,kvm "$user"
    done
    
    # still required?
    echo "firewall_backend  = \"iptables\"" >> /etc/libvirt/network.conf
}

setup_camera() {
    # https://mozilla.github.io/webrtc-landing/gum_test.html
    # xps 9340 - ov02c10
    dnf -y remove akmod-intel-ipu6 'kmod-intel-ipu6*'
    dnf -y install libcamera-qcam libcamera-tools
    cam -l
    dmesg | grep -i ipu6
}

setup_tlp() {
    dnf -y remove tuned tuned-ppd power-profiles-daemon
    dnf -y install tlp tlp-rdw smartmontools
    # Drop-in rather than overwriting /etc/tlp.conf, which is 574 lines of
    # documented defaults shipped by the package. The packaged file leaves
    # every setting commented out, so it overrides nothing here.
    echo '
TLP_ENABLE=1
TLP_AUTO_SWITCH=1
TLP_DEFAULT_MODE=BAL
CPU_SCALING_GOVERNOR_ON_AC=performance
CPU_SCALING_GOVERNOR_ON_BAT=powersave
CPU_ENERGY_PERF_POLICY_ON_AC=balance_performance
CPU_ENERGY_PERF_POLICY_ON_BAT=balance_power
MEM_SLEEP_ON_AC=s2idle
MEM_SLEEP_ON_BAT=s2idle
USB_AUTOSUSPEND=0
USB_EXCLUDE_AUDIO=1
USB_EXCLUDE_PHONE=1
USB_EXCLUDE_BTUSB=1
RESTORE_THRESHOLDS_ON_BAT=1
' > /etc/tlp.d/99-local.conf
    systemctl enable tlp.service
    systemctl start tlp.service
    systemctl mask systemd-rfkill.service systemd-rfkill.socket
    tlp-stat -s
}

ask_reboot() {
    echo 'Reboot now? (y/n)'
    while true; do
        read choice
        if [[ "$choice" == 'y' || "$choice" == 'Y' ]]; then
            reboot
            exit 0
        fi
        if [[ "$choice" == 'n' || "$choice" == 'N' ]]; then
            break
        fi
    done
}

msg() {
    tput setaf 2
    echo "[*] $1"
    tput sgr0
}

error_msg() {
    tput setaf 1
    echo "[!] $1"
    tput sgr0
}

check_root_user() {
    if [ "$(id -u)" != 0 ]; then
        echo 'Please run the script as root!'
        echo 'We need to do administrative tasks'
        exit 1
    fi
}

show_menu() {
    echo 'Choose what to do: '
    echo '1 - Run script.'
    echo 'q - Exit'
    echo
}

main() {
    check_root_user
    while true; do
        show_menu
        read -p 'Enter your choice: ' choice
        case $choice in
        1)
            auto
            msg 'Done!'
            ask_reboot
            ;;
        q)
            exit 0
            ;;
        *)
            error_msg 'Wrong input!'
            ;;
        esac
    done

}

auto() {
    msg 'Setting up swap'
    setup_zram
    msg 'Setting up locale'
    setup_locale
    msg 'Updating system'
    update_system
    msg 'Install external repos'
    install_external_repos
    msg 'Installing packages'
    install_packages
    msg 'Setting up flatpak'
    setup_flatpak
    msg 'Setting up containers'
    setup_podman
    msg 'Setting up firewall'
    setup_firewall
    msg 'Installing MS fonts'
    setup_fonts
    msg 'Installing veracrypt'
    install_veracrypt
    msg 'Installing coding tools'
    install_cursor
    #install_vscode
    install_claude
    msg 'Disabling smart card'
    disable_smart_card
    msg 'Installing qemu'
    install_qemu
    #msg 'Setup camera (experimental)'
    #setup_camera
    msg 'Setting up tlp'
    setup_tlp
}

(return 2> /dev/null) || main
