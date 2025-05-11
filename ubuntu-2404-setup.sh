#!/usr/bin/env bash

remove_unattended_upgrades() {
    systemctl disable --now unattended-upgrades
    apt remove unattended-upgrades -y
    echo '
Package: unattended-upgrades
Pin: release a=*
Pin-Priority: -10
' > /etc/apt/preferences.d/nounattended.pref
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

update_system() {
    apt update && apt upgrade -y
}

cleanup() {
    apt autoremove -y
}

install_basic_packages() {
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
        hplip keepassxc  synaptic default-jre audacity -y
    apt install solaar -y # logi bolt
}

setup_podman() {
    apt install podman podman-docker podman-compose -y
    echo '
unqualified-search-registries = ["docker.io"]
' >> /etc/containers/registries.conf
}

setup_docker() {
    apt-get remove docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc -y
    apt-get update -y
    apt-get install ca-certificates curl -y
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc

    echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
    tee /etc/apt/sources.list.d/docker.list > /dev/null
    apt-get update -y

    apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y

    systemctl enable --now docker

    # groupadd docker
    for userpath in /home/*; do
        usermod -a -G docker $(basename $userpath)
    done 
}


setup_fonts() {
    echo ttf-mscorefonts-installer msttcorefonts/accepted-mscorefonts-eula select true | debconf-set-selections    
    apt install ttf-mscorefonts-installer -y
}

setup_flathub() {
    apt install flatpak -y
    flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
    flatpak install com.github.tchx84.Flatseal -y
}

setup_zram() {
    apt install zram-tools -y
    echo -e "ALGO=zstd\nPERCENT=20" | tee -a /etc/default/zramswap
    systemctl restart zramswap
    swapon -s
}

setup_tlp() {
    apt install tlp tlp-rdw smartmontools -y
    apt remove power-profiles-daemon -y
    echo '
TLP_ENABLE=1
CPU_SCALING_GOVERNOR_ON_BAT=powersave
RESTORE_THRESHOLDS_ON_BAT=1
USB_AUTOSUSPEND=0
USB_EXCLUDE_AUDIO=1
USB_EXCLUDE_PHONE=1
USB_EXCLUDE_BTUSB=1
' > /etc/tlp.conf 
    systemctl enable tlp.service
    systemctl start tlp.service
    systemctl mask systemd-rfkill.service systemd-rfkill.socket
    tlp-stat -s
}

install_chrome() {
    wget https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
    apt install ./google-chrome-stable_current_amd64.deb -y
    rm -f google-chrome-stable_current_amd64.deb
}

install_veracrypt() {
    export VC_VERSION="1.26.20"
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
    flatpak -y install org.freeplane.App
}

install_qemu() {
    systemctl stop pcscd.socket
    systemctl stop pcscd
    systemctl disable pcscd
    systemctl mask pcscd
    apt install qemu-system qemu-kvm libvirt-daemon libvirt-clients bridge-utils virt-manager libvirt-daemon-system \
        virtinst qemu-utils virt-viewer spice-client-gtk gir1.2-spice* ebtables swtpm swtpm-tools ovmf virtiofsd -y
    virsh net-autostart default
    modprobe vhost_net    
    for userpath in /home/*; do
        usermod -a -G libvirt,kvm $(basename $userpath)
    done    
}

install_vbox() {
    apt install binutils build-essential make dkms linux-headers-$(uname -r) linux-headers-generic virtualbox virtualbox-dkms virtualbox-ext-pack -y
    for userpath in /home/*; do
        usermod -a -G vboxusers $(basename $userpath)
    done    
}


setup_firewall() {
    apt install ufw gufw -y
    systemctl stop ssh.socket ssh
    systemctl disable ssh
    ufw enable    
    ufw default deny incoming
    ufw default allow outgoing
    ufw status verbose
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
    msg 'Updating system'
    update_system
    msg 'Removing unattended upgrades'
    remove_unattended_upgrades
    msg 'Removing mozilla snaps'
    remove_mozilla_snaps
    msg 'Installing Firefox and Thunderbird (DEB)'
    install_mozilla_apps
    msg 'Setting up zram'
    setup_zram    
    msg 'Installing basic packages'
    install_basic_packages
    msg 'Setting up flathub'
    setup_flathub    
    msg 'Setting up TLP'
    setup_tlp
    msg 'Setting up firewall'
    setup_firewall
    msg 'Installing extra packages'
    install_extra_packages
    msg 'Setup containers'
    #setup_podman
    setup_docker
    msg 'Install MS fonts'
    setup_fonts
    #msg 'Install chrome'
    #install_chrome
    msg 'Install veracrypt'
    install_veracrypt
    msg 'Install code'
    install_vscode
    msg 'Install freeplane'
    install_freeplane
    msg 'Install qemu'
    install_qemu
    #msg 'Install vbox'
    #install_vbox
    msg 'Cleaning up'
    cleanup
}

(return 2> /dev/null) || main
