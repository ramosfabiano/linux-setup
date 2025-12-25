#!/usr/bin/env bash

setup_zram() {
    apt install zram-tools -y
    echo -e "ALGO=zstd\nPERCENT=15" | tee -a /etc/default/zramswap
    systemctl restart zramswap
    swapon -s
    sed -i '/^\/dev\/mapper\/.*vg-swap/s/^/#/' /etc/fstab
    swapoff /dev/dm-2
    mount -a
    swapon -s
}

setup_locale() {
    sed -i 's/^# *\(pt_BR\.UTF-8\)/\1/' /etc/locale.gen
    cat /etc/locale.gen | grep -v ^#
    locale-gen
}

update_system() {
    apt modernize-sources -y
    rm -f /etc/apt/sources.list~ /etc/apt/sources.list.bak
    sed -i '/^Components:/ s/$/ contrib non-free/' /etc/apt/sources.list.d/debian.sources
    apt update
    apt upgrade -y
}

install_backports_repo() {
    echo '
Types: deb deb-src
URIs: http://deb.debian.org/debian
Suites: trixie-backports
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
' > /etc/apt/sources.list.d/trixie-backports.sources
    apt update
}

setup_flatpak() {
    apt install flatpak -y
    flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
    flatpak -y install com.github.tchx84.Flatseal
}

install_packages() {
    apt install --install-suggests gnome-software -y
    apt install intel-microcode firmware-linux firmware-linux-nonfree firmware-misc-nonfree dkms -y

    apt install openntpd vim net-tools rsync openssh-server flatpak vim net-tools \
        vim build-essential ffmpeg libavcodec-extra gstreamer1.0-* gstreamer1.0-plugins* \
        gnome-shell-extension-appindicator tigervnc-viewer dnsutils \
	 	astyle inxi vlc texlive-extra-utils graphicsmagick-imagemagick-compat  \
        python3-pip pipx apt-transport-https ca-certificates curl wget \
        fonts-liberation libu2f-udev libvulkan1 gnome-shell-extension-dashtodock \
		git xsel gnome-tweaks gnome-shell-extension-prefs gnome-shell-extensions \
        hplip synaptic default-jre chromium thunderbird solaar \
        gimp audacity keepassxc yt-dlp tree -y
}

setup_firefox() {
    flatpak -y install flathub org.mozilla.firefox
}

setup_podman() {
    apt install podman podman-compose podman-docker -y
    echo '
[registries.search]
registries = ["docker.io"]
[registries.insecure]
registries = []
[registries.block]
registries = []
' >> /etc/containers/registries.conf
}

setup_fonts() {
    echo ttf-mscorefonts-installer msttcorefonts/accepted-mscorefonts-eula select true | debconf-set-selections    
    apt install ttf-mscorefonts-installer -y
}

setup_firewall() {
    apt install ufw gufw -y
    systemctl stop ssh.socket ssh
    systemctl disable ssh
    ufw enable
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow mdns
    ufw status verbose
}

install_veracrypt() {
    export VC_VERSION="1.26.24"
    wget https://launchpad.net/veracrypt/trunk/$VC_VERSION/+download/veracrypt-$VC_VERSION-Debian-13-amd64.deb
    wget https://launchpad.net/veracrypt/trunk/$VC_VERSION/+download/veracrypt-$VC_VERSION-Debian-13-amd64.deb.sig
    wget https://www.idrix.fr/VeraCrypt/VeraCrypt_PGP_public_key.asc
    gpg --import VeraCrypt_PGP_public_key.asc
    gpg --verify veracrypt-$VC_VERSION-Debian-13-amd64.deb.sig
    apt install ./veracrypt-$VC_VERSION-Debian-13-amd64.deb -y
    rm -f veracrypt-$VC_VERSION-Debian-13-amd64.deb
    rm -f veracrypt-$VC_VERSION-Debian-13-amd64.deb.sig
    rm -f VeraCrypt_PGP_public_key.asc
    rm -f VeraCrypt_PGP_public_key.asc.1   
}

install_vscode() {
    apt -y install wget gpg apt-transport-https
    wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > microsoft.gpg
    sudo install -D -o root -g root -m 644 microsoft.gpg /usr/share/keyrings/microsoft.gpg
    rm -f microsoft.gpg
    echo '
Types: deb
URIs: https://packages.microsoft.com/repos/code
Suites: stable
Components: main
Architectures: amd64,arm64,armhf
Signed-By: /usr/share/keyrings/microsoft.gpg
' > /etc/apt/sources.list.d/vscode.sources
    apt update -y
    apt install code -y
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
    msg 'Setting up locale'
    setup_locale
    msg 'Updating system'
    update_system
    msg 'Installing backports repo'
    install_backports_repo
    msg 'Installing packages'
    install_packages
    msg 'Setting up flatpak'
    setup_flatpak
    msg 'Setting up firefox'
    setup_firefox
    msg 'Setting up containers'
    setup_podman
    msg 'Setting up firewall'
    setup_firewall
    msg 'Installing MS fonts'
    setup_fonts
    msg 'Installing veracrypt'
    install_veracrypt
    msg 'Installing code'
    install_vscode
    msg 'Disabling smart card'
    disable_smart_card
    msg 'Installing qemu'
    install_qemu
}

(return 2> /dev/null) || main
