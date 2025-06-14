#!/usr/bin/env bash

update_system() {
    dnf -y update
}

install_rpmfusion() {
    dnf -y install https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm 
    dnf -y install https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm
    dnf -y update
}

setup_flatpak() {
    flatpak -y install fedora com.github.tchx84.Flatseal
    #flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
}

install_basic_packages() {
    dnf -y install flatpak vim filezilla thunderbird tigervnc git meld  \
        vlc cmake gcc-c++ boost-devel flatpak thunderbird vim unrar  \
        tigervnc dnsutils java-latest-openjdk astyle  \
        containernetworking-plugins meld thermald curl wget liberation*fonts* \
        python3-pip pipx xsel inxi vlc firewall-config gnome-icon-theme \
        hplip hplip-gui cabextract lzip p7zip p7zip-plugins unrar \
        gnome-tweaks gnome-shell-extension-common.noarch gnome-extensions-app \
        gnome-shell-extension-dash-to-dock gnome-shell-extension-appindicator \
        gdk-pixbuf2-modules-extra chromium v4l-utils
}

install_extra_packages() {
    dnf -y install amrnb amrwb faad2 flac gpac-libs lame libde265 libfc14audiodecoder mencoder x264 x265 --allowerasing
    dnf -y install ffmpeg-libs libva libva-utils
    dnf -y libva-intel-media-driver intel-media-driver --allowerasing
    dnf -y install libva-intel-driver
}

install_extra_packages_flatpak() {
    flatpak -y install flathub org.gimp.GIMP
    flatpak -y install flathub org.audacityteam.Audacity 
    flatpak -y install flathub org.keepassxc.KeePassXC 
    flatpak -y install flathub io.github.pwr_solaar.solaar
    flatpak -y install flathub org.freeplane.App
}

setup_podman() {
    dnf -y install podman podman-compose podman-docker
}

setup_fonts() {
    dnf -y install curl cabextract xorg-x11-font-utils fontconfig
    rpm -i https://downloads.sourceforge.net/project/mscorefonts2/rpms/msttcore-fonts-installer-2.6-1.noarch.rpm
}

setup_firewall() {
    systemctl disable sshd
    firewall-cmd --set-default-zone public
    firewall-cmd --permanent --remove-service=ssh
    firewall-cmd --permanent --remove-service=dhcpv6-client
    firewall-cmd --reload
    firewall-cmd --list-all
}

install_veracrypt() {
    export VC_VERSION="1.26.24"
    cd /tmp
    wget https://launchpad.net/veracrypt/trunk/$VC_VERSION/+download/veracrypt-$VC_VERSION-Fedora-40-x86_64.rpm
    wget https://launchpad.net/veracrypt/trunk/$VC_VERSION/+download/veracrypt-$VC_VERSION-Fedora-40-x86_64.rpm.sig
    wget https://www.idrix.fr/VeraCrypt/VeraCrypt_PGP_public_key.asc
    gpg --import VeraCrypt_PGP_public_key.asc
    gpg --verify veracrypt-$VC_VERSION-Fedora-40-x86_64.rpm.sig
    sudo dnf -y install ./veracrypt*.rpm
    rm -f VeraCrypt* veracrypt*  
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

disable_smart_card() {
    systemctl stop pcscd.socket
    systemctl stop pcscd
    systemctl disable pcscd
    systemctl mask pcscd
}

install_qemu() {
    dnf -y install bridge-utils libvirt virt-install qemu-kvm virt-viewer virt-manager spice-webdavd spice-gtk-tools swtpm.x86_64 edk2-ovmf  
    sed -i 's/^SELINUX=.*/SELINUX=permissive/' /etc/selinux/config
    setenforce 0
    for userpath in /home/*; do
        usermod -a -G libvirt,kvm $(basename $userpath)
    done    
}

fix_libvirt_network() {
    echo "firewall_backend  = \"iptables\"" >> /etc/libvirt/network.conf
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
    msg 'Install rpmfusion'
    install_rpmfusion
    msg 'Installing basic packages'
    install_basic_packages
    msg 'Installing extra packages'
    install_extra_packages
    msg 'Setting up flatpak'
    setup_flatpak
    install_extra_packages_flatpak
    msg 'Setup containers'
    setup_podman 
    msg 'Setting up firewall'
    setup_firewall
    msg 'Install MS fonts'
    setup_fonts
    msg 'Install veracrypt'
    install_veracrypt
    msg 'Install code'
    install_vscode
    msg 'Disable smart card'
    disable_smart_card
    msg 'Install qemu'
    install_qemu
    msg 'Libvirt network fix'
    fix_libvirt_network
}

(return 2> /dev/null) || main
