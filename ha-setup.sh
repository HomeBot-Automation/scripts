#!/bin/bash

check_deb_installed() {
    local deb_file="$1"
    
    if [[ ! -f "$deb_file" ]]; then
        echo "File not found: $deb_file"
        return 1
    fi
    
    # Extract the package name from the .deb file
    local package_name=$(dpkg --info "$deb_file" | grep "Package:" | awk '{print $2}')
    
    if [[ -z "$package_name" ]]; then
        echo "Failed to extract package name from: $deb_file"
        return 1
    fi
    
    # Check if the package is installed
    local status=$(dpkg-query -W -f='${Status}' "$package_name" 2>/dev/null)
    
    if [[ "$status" == "install ok installed" ]]; then
        echo "Package '$package_name' from '$deb_file' is already installed."
        return 0
    else
        echo "Package '$package_name' from '$deb_file' is not installed."
        return 1
    fi
}

# Check if apt repo has already been set up
if [ $(grep -c "deb.homebotautomation.com" /etc/apt/sources.list) -eq 0 ]; then
    # Backup apt's sources.list
    sudo mv /etc/apt/sources.list /etc/apt/sources.list.bak
    # Remove unnecessary architecture
    sudo dpkg --remove-architecture armhf
    # set up our debian repo as the apt source
    echo "deb http://deb.homebotautomation.com/debian bullseye main" | sudo tee /etc/apt/sources.list
fi
if [ ! -f /etc/apt/trusted.gpg.d/homebotautomation.gpg ]; then
    # Add repo's public key
    sudo curl -sSL http://deb.homebotautomation.com/public.key -o /etc/apt/trusted.gpg.d/homebotautomation.gpg
fi
if [ ! -f /etc/stub-resolv.conf ]; then
    # copy working resolv.conf file
    sudo cp /etc/resolv.conf /etc/stub-resolv.conf
fi
# update the system
sudo apt update
sudo apt upgrade -y
# install home assistant required packages
sudo apt install -y apparmor cifs-utils curl dbus jq libglib2.0-bin lsb-release network-manager nfs-common systemd-journal-remote systemd-resolved udisks2 wget libcgroup1
# enable apparmor and cgroup v1 to make home assistant happy
if [ $(grep -c "apparmor" /boot/orangepiEnv.txt) -eq 0 ]; then
    sudo sed -i 's/extraargs=cma=64M/extraargs=cma=64M apparmor=1 security=apparmor systemd.unified_cgroup_hierarchy=0/g' /boot/orangepiEnv.txt
fi
sudo systemctl enable apparmor
# replace new resolv.conf symlink with a symlink to a resolv.conf file that works
sudo rm -f /etc/resolv.conf
sudo ln -s /etc/stub-resolv.conf /etc/resolv.conf
# install home assistant os-agent
if [! -f os-agent_1.6.0_linux_aarch64.deb ]; then
    wget https://github.com/home-assistant/os-agent/releases/download/1.6.0/os-agent_1.6.0_linux_aarch64.deb
fi
if ! check_deb_installed ./os-agent_1.6.0_linux_aarch64.deb; then
    sudo dpkg -i ./os-agent_1.6.0_linux_aarch64.deb
fi
# install home assistant supervisor
# when prompted to select machine type, I selected raspberrypi4-64
if [ ! -f homeassistant-supervised.deb ]; then
    wget -O homeassistant-supervised.deb https://github.com/home-assistant/supervised-installer/releases/latest/download/homeassistant-supervised.deb
fi
if ! check_deb_installed ./homeassistant-supervised.deb; then
    sudo apt install -y ./homeassistant-supervised.deb
fi
/usr/sbin/reboot
