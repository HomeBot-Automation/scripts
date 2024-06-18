#!/bin/bash

# Backup apt's sources.list
sudo mv /etc/apt/sources.list /etc/apt/sources.list.bak
# Remove unnecessary architecture
sudo dpkg --remove-architecture armhf
# set up our debian repo as the apt source
echo "deb http://deb.homebotautomation.com/debian bullseye main" | sudo tee /etc/apt/sources.list
# Add repo's public key
sudo curl -sSL http://deb.homebotautomation.com/public.key -o /etc/apt/trusted.gpg.d/homebotautomation.gpg
# copy working resolv.conf file
sudo cp /etc/resolv.conf /etc/stub-resolv.conf
# update the system
sudo apt update
sudo apt upgrade -y
# install home assistant required packages
sudo apt install -y apparmor cifs-utils curl dbus jq libglib2.0-bin lsb-release network-manager nfs-common systemd-journal-remote systemd-resolved udisks2 wget libcgroup1
# enable apparmor and cgroup v1 to make home assistant happy
sudo sed -i 's/extraargs=cma=64M/extraargs=cma=64M apparmor=1 security=apparmor systemd.unified_cgroup_hierarchy=0/g' /boot/orangepiEnv.txt
sudo systemctl enable apparmor
# replace new resolv.conf symlink with a symlink to a resolv.conf file that works
sudo rm -f /etc/resolv.conf
sudo ln -s /etc/stub-resolv.conf /etc/resolv.conf
# install home assistant os-agent
wget https://github.com/home-assistant/os-agent/releases/download/1.6.0/os-agent_1.6.0_linux_aarch64.deb
sudo dpkg -i ./os-agent_1.6.0_linux_aarch64.deb
# install home assistant supervisor
# when prompted to select machine type, I selected raspberrypi4-64
wget -O homeassistant-supervised.deb https://github.com/home-assistant/supervised-installer/releases/latest/download/homeassistant-supervised.deb
sudo apt install -y ./homeassistant-supervised.deb
/usr/sbin/reboot
