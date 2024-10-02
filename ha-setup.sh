#!/bin/bash

# Set TESTING to a default value 0 if it is not already set
: ${TESTING:=0}

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

# set timezone to mountain time
sudo timedatectl set-timezone America/Denver

# sync time with NTP servers
sudo chronyc -a 'burst 4/4'
sleep 5

if [ -e /etc/apt/sources.list.d/docker.list ]; then
    sudo rm -rvf /etc/apt/sources.list.d/docker.list
    until sudo apt update; do
        sleep 5
    done
    sudo apt purge -y ~ndocker
fi
if [ $TESTING -gt 0 ]; then
    if [ $(grep -c "deb.debian.org" /etc/apt/sources.list) -eq 0 ]; then
        sudo mv /etc/apt/sources.list /etc/apt/sources.list.bak
        cat <<EOF | sudo tee /etc/apt/sources.list
# Debian Bookworm
deb http://deb.debian.org/debian bookworm main contrib non-free non-free-firmware
#deb-src http://deb.debian.org/debian bookworm main contrib non-free non-free-firmware

deb http://deb.debian.org/debian bookworm-updates main contrib non-free non-free-firmware
#deb-src http://deb.debian.org/debian bookworm-updates main contrib non-free non-free-firmware

deb http://deb.debian.org/debian bookworm-backports main contrib non-free non-free-firmware
#deb-src http://deb.debian.org/debian bookworm-backports main contrib non-free non-free-firmware

deb http://security.debian.org/debian-security bookworm-security main contrib non-free non-free-firmware
#deb-src http://security.debian.org/debian-security bookworm-security main contrib non-free non-free-firmware
EOF
    fi
fi
if [ $TESTING -eq 0 ]; then
    # Check if apt repo has already been set up
    if [ $(grep -c "deb.homebotautomation.com" /etc/apt/sources.list) -eq 0 ]; then
        # Backup apt's sources.list
        sudo mv /etc/apt/sources.list /etc/apt/sources.list.bak
        # Remove unnecessary architecture
        # sudo dpkg --remove-architecture armhf
        # set up our debian repo as the apt source
        echo "deb https://deb.homebotautomation.com/debian bookworm main" | sudo tee /etc/apt/sources.list
    fi
    if [ ! -f /etc/apt/trusted.gpg.d/homebotautomation.gpg ]; then
        # Add repo's public key
        sudo curl -sSL http://deb.homebotautomation.com/public.key -o /etc/apt/trusted.gpg.d/homebotautomation.gpg
    fi
fi
if [ ! -f /etc/stub-resolv.conf ]; then
    # copy working resolv.conf file
    sudo cp /etc/resolv.conf /etc/stub-resolv.conf
fi
# update the system
until sudo apt update; do
    sleep 15
done
sleep 5
sudo apt upgrade -y
# install home assistant required packages
sudo apt install -y apparmor cifs-utils curl dbus jq libglib2.0-bin lsb-release network-manager nfs-common systemd-journal-remote systemd-resolved udisks2 wget cgroup-tools
# enable apparmor and cgroup v1 to make home assistant happy
if [ $(grep -c "apparmor" /boot/orangepiEnv.txt) -eq 0 ]; then
    sudo sed -i 's/extraargs=cma=128M/extraargs=cma=128M apparmor=1 security=apparmor systemd.unified_cgroup_hierarchy=0/g' /boot/orangepiEnv.txt
fi
sudo systemctl enable apparmor
# replace new resolv.conf symlink with a symlink to a resolv.conf file that works
sudo rm -f /etc/resolv.conf
sudo ln -s /etc/stub-resolv.conf /etc/resolv.conf
if [ $TESTING -gt 0 ]; then
    if ! check_deb_installed docker-ce; then
        sleep 5
        # Add Docker's official GPG key:
        sudo apt update
        sudo install -m 0755 -d /etc/apt/keyrings
        sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
        sudo chmod a+r /etc/apt/keyrings/docker.asc

        # Add the repository to Apt sources:
        echo \
          "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
          $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
          sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
        sudo apt update
    fi
fi
sleep 5
if ! check_deb_installed docker-ce; then
    sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi
if [ $TESTING -eq 0 ]; then
    if [ ! -f /usr/bin/auto-update ]; then
        sudo cp auto-update /usr/bin
    fi
    # Define the cron job entry
    CRON_JOB="*/15 * * * * /usr/bin/auto-update"

    # Add the cron job to the crontab if it's not already present
    (sudo crontab -l | grep -F "$CRON_JOB") || (sudo crontab -l; echo "$CRON_JOB") | sudo crontab -
fi
# install home assistant os-agent
if [ ! -f os-agent_1.6.0_linux_aarch64.deb ]; then
    until wget -O os-agent.temp https://version.homebotautomation.com/os-agent_1.6.0_linux_aarch64.deb; do
	rm os-agent.temp
	sleep 15
    done
    mv os-agent.temp os-agent_1.6.0_linux_aarch64.deb
fi
if ! check_deb_installed ./os-agent_1.6.0_linux_aarch64.deb; then
    sudo dpkg -i ./os-agent_1.6.0_linux_aarch64.deb
fi
# install home assistant supervisor
# when prompted to select machine type, I selected raspberrypi4-64
if [ ! -f homeassistant-supervised.deb ]; then
    until wget -O homeassistant-supervised.temp https://version.homebotautomation.com/homeassistant-supervised.deb; do
        rm homeassistant-supervised.temp
	sleep 15
    done
    mv homeassistant-supervised.temp homeassistant-supervised.deb
fi
if ! check_deb_installed ./homeassistant-supervised.deb; then
    sudo apt install -y ./homeassistant-supervised.deb
fi
cd ..
rm -rvf scripts
history -c
rm -rvf ~/.bash_history
history -w
history -c
sync
systemctl reboot -i
