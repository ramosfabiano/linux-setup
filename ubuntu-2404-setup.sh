#!/usr/bin/env bash

setup_zram() {
    apt install zram-tools -y
    echo -e "ALGO=zstd\nPERCENT=15" | tee -a /etc/default/zramswap
    systemctl restart zramswap
    swapon -s
}

remove_unattended_upgrades() {
    systemctl disable --now unattended-upgrades
    apt remove unattended-upgrades -y
    echo '
Package: unattended-upgrades
Pin: release a=*
Pin-Priority: -10
' > /etc/apt/preferences.d/nounattended.pref
}

update_system() {
    apt update && apt upgrade -y
}


remove_mozilla_snaps() {
    remove_unattended_upgrades
    snap remove --purge thunderbird
    apt remove thunderbird -y
    snap remove --purge firefox
    apt remove firefox -y
}

install_mozilla_apps() {
    apt install wget -y
    # official mozilla
    install -d -m 0755 /etc/apt/keyrings
    wget -q https://packages.mozilla.org/apt/repo-signing-key.gpg -O- | tee /etc/apt/keyrings/packages.mozilla.org.asc
    echo "deb [signed-by=/etc/apt/keyrings/packages.mozilla.org.asc] https://packages.mozilla.org/apt mozilla main" | tee -a /etc/apt/sources.list.d/mozilla.list
     # mozilla team ppa, as a fallback
    add-apt-repository ppa:mozillateam/ppa -y
    # setup priorities
    echo '
Package: *
Pin: origin packages.mozilla.org
Pin-Priority: 1001

Package: thunderbird*
Pin: release o=LP-PPA-mozillateam
Pin-Priority: 1000

Package: thunderbird*
Pin: release o=Ubuntu
Pin-Priority: -1

Package: firefox*
Pin: release o=Ubuntu
Pin-Priority: -1
' > /etc/apt/preferences.d/mozilla
    apt update
    apt install firefox thunderbird -y
}

setup_flatpak() {
    apt install flatpak -y
    flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
    flatpak -y install com.github.tchx84.Flatseal
}

install_packages() {
    apt install vim net-tools rsync openssh-server -y
    apt install --install-suggests gnome-software -y
}

install_extra_packages() {
    apt install ntp flatpak vim net-tools vim build-essential ffmpeg  rar unrar  \
	 	p7zip-rar libavcodec-extra gstreamer1.0-* gstreamer1.0-plugins* \
        gnome-shell-extension-appindicator tigervnc-viewer dnsutils \
	 	meld astyle inxi vlc texlive-extra-utils graphicsmagick-imagemagick-compat  \
        python3-pip pipx apt-transport-https ca-certificates curl software-properties-common wget \
        fonts-liberation libu2f-udev libvulkan1 \
		git xsel gnome-tweaks gnome-shell-extension-prefs gnome-shell-extensions \
        hplip keepassxc  synaptic default-jre audacity solaar yt-dlp tree -y
}

setup_podman() {
    apt install podman podman-compose podman-docker -y
    echo '
unqualified-search-registries = ["docker.io"]
' >> /etc/containers/registries.conf
}

setup_fonts() {
    echo ttf-mscorefonts-installer msttcorefonts/accepted-mscorefonts-eula select true | debconf-set-selections    
    apt install ttf-mscorefonts-installer -y
}

setup_firewall() {
    apt install ufw gufw -y
    systemctl stop ssh.socket ssh
    systemctl disable ssh.socket ssh
    ufw enable
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow mdns
    ufw status verbose
}

install_veracrypt() {
    export VC_VERSION="1.26.24"
    wget https://launchpad.net/veracrypt/trunk/$VC_VERSION/+download/veracrypt-$VC_VERSION-Ubuntu-24.04-amd64.deb
    wget https://launchpad.net/veracrypt/trunk/$VC_VERSION/+download/veracrypt-$VC_VERSION-Ubuntu-24.04-amd64.deb.sig
    wget https://www.idrix.fr/VeraCrypt/VeraCrypt_PGP_public_key.asc
    gpg --import VeraCrypt_PGP_public_key.asc
    gpg --verify veracrypt-$VC_VERSION-Ubuntu-24.04-amd64.deb.sig
    apt install ./veracrypt-$VC_VERSION-Ubuntu-24.04-amd64.deb -y
    rm -f veracrypt-$VC_VERSION-Ubuntu-24.04-amd64.deb
    rm -f veracrypt-$VC_VERSION-Ubuntu-24.04-amd64.deb.sig
    rm -f VeraCrypt_PGP_public_key.asc
    rm -f VeraCrypt_PGP_public_key.asc.1   
}

install_vscode() {
    wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > packages.microsoft.gpg
    install -D -o root -g root -m 644 packages.microsoft.gpg /etc/apt/keyrings/packages.microsoft.gpg
    sh -c 'echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" > /etc/apt/sources.list.d/vscode.list'
    rm -f packages.microsoft.gpg
    apt update -y
    apt install code -y
}

install_freeplane() {
    flatpak -y install flathub org.freeplane.App
}

disable_smart_card() {
    systemctl stop pcscd.socket
    systemctl stop pcscd
    systemctl disable pcscd
    systemctl mask pcscd
}

install_qemu() {
    apt install qemu-system qemu-kvm libvirt-daemon libvirt-clients bridge-utils virt-manager libvirt-daemon-system \
        virtinst qemu-utils virt-viewer spice-client-gtk gir1.2-spice* ebtables swtpm swtpm-tools ovmf virtiofsd -y
    virsh net-autostart default
    modprobe vhost_net    
    for userpath in /home/*; do
        usermod -a -G libvirt,kvm $(basename $userpath)
    done    
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
    sleep 5
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
        exit
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
    msg 'Updating system'
    update_system
    msg 'Removing unattended upgrades'
    remove_unattended_upgrades
    msg 'Removing mozilla snaps'
    remove_mozilla_snaps
    msg 'Installing Firefox and Thunderbird (DEB)'
    install_mozilla_apps
    msg 'Installing packages'
    install_packages
    msg 'Setting up flatpak'
    setup_flatpak
    msg 'Setting up firewall'
    setup_firewall
    msg 'Installing extra packages'
    install_extra_packages
    msg 'Setting up containers'
    setup_podman
    msg 'Install MS fonts'
    setup_fonts
    msg 'Install veracrypt'
    install_veracrypt
    msg 'Install code'
    install_vscode
    msg 'Install freeplane'
    install_freeplane
    msg 'Disabling smart card'
    disable_smart_card
    msg 'Install qemu'
    install_qemu
}

(return 2> /dev/null) || main
