#!/bin/bash

if [[ $USER != "root" ]]; then
    sudo "$0"
    exit 0
fi

#Set Display name to Employee Name

echo "What is the Employee's First name?" 
read employee_first_name
echo "What is the Employee's Gram?" 
read employee_gram

chfn -f "$employee_first_name ($employee_gram)" odoo

export DEBIAN_FRONTEND=noninteractive

#Change updates mirror

sed -i -e s,http://be.archive.ubuntu.com/ubuntu/,http://archive.ubuntu.com/ubuntu/,g /etc/apt/sources.list.d/ubuntu.sources

#Remove Canon Drivers

dpkg -P cnrdrvcups-ufr2-us
dpkg -P cnrdrvcups-ufr2-uk
dpkg -P cnrdrvcups-lipslx

#Uninstall deb apps

for f in `cat ./uninstall-deb-apps.txt` ; do apt remove -y $f ; done

#Remove old or invalid deb repos

rm -rf /etc/apt/sources.list.d/mozilla.list

#Install New deb packages

#Warp Terminal

dpkg -i ./warp-terminal_*_amd64.deb

#VScode

dpkg -i ./code_*_amd64.deb

#Balena Etcher

sudo dpkg -i ./balena-etcher_*_amd64.deb

#Install dbus-x11

apt install -y dbus-x11

#Remove Google Chrome user confuration

rm -rf /home/odoo/.config/google-chrome

#Remove Google Chrome System Defaults

rm -rf /etc/default/google-chrome

#Apt, update, upgrade and autoremove

apt update && sudo apt upgrade -y
apt apt autoremove -y

#Install flatpaks from USB Drive

flatpak remote-modify --collection-id=org.flathub.Stable flathub
for f in `cat ./flatpaks_install.txt` ; do flatpak install --sideload-repo=./flatpaks/.ostree/repo flathub -y $f ; done

#Manual Flatpak installs

#Zoom

flatpak install -y app/us.zoom.Zoom/x86_64/stable

#Update Flatpaks

flatpak update -y

#Set Icon Arrangement and settings

