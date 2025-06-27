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

sed -i -e s,http://be.archive.ubuntu.com/ubuntu/,http://us.archive.ubuntu.com/ubuntu/,g /etc/apt/sources.list.d/ubuntu.sources

#Remove Canon Drivers

dpkg -P cnrdrvcups-ufr2-uk

#Stop packagekitd

systemctl stop packagekit.service

#Stop unattended-upgrades

systemctl stop unattended-upgrades.service

sleep 60

#Remove snap store

snap remove snap-store

#Uninstall deb apps

for f in `cat ./uninstall-deb-apps.txt` ; do apt remove -y $f ; done

#Remove old or invalid deb repos

rm -rf /etc/apt/sources.list.d/mozilla.list

#Install New deb packages

apt update && apt upgrade -y && apt autoremove -y 

#Install dbus-x11

apt install -y dbus-x11

#Warp Terminal

dpkg -i ./warp-terminal_*_amd64.deb

#VScode

dpkg -i ./code_*_amd64.deb

#Balena Etcher

dpkg -i ./balena-etcher_*_amd64.deb

#Remove Google Chrome user confuration

rm -rf /home/odoo/.config/google-chrome

#Remove Google Chrome System Defaults

rm -rf /etc/default/google-chrome

#Remove gnome keyrings for user odoo

rm -rf /home/odoo/.local/share/keyrings/*

#Apt, update, upgrade and autoremove

apt update && apt --fix-broken install -y && apt upgrade -y
apt autoremove -y

#Install flatpaks from USB Drive

flatpak remote-modify --collection-id=org.flathub.Stable flathub
for f in `cat ./flatpaks_install.txt` ; do flatpak install --sideload-repo=./flatpaks/.ostree/repo flathub -y $f ; done

#Manual Flatpak installs

#Zoom

flatpak install -y app/us.zoom.Zoom/x86_64/stable

#Update Flatpaks

flatpak update -y

#Set Icon Arrangement and settings

sudo -u odoo bash -c 'dconf load / < odoo-gnome-arrangement.txt'

#Set Wallpapers

mkdir -p /opt/odoo/wallpapers/

cp ./wallpapers/* /opt/odoo/wallpapers/

sudo -u odoo bash -c 'dconf write /org/gnome/desktop/background/picture-uri "'file:///opt/odoo/wallpapers/odoo-wallpaper-tips-light.png'"'

sudo -u odoo bash -c 'dconf write /org/gnome/desktop/background/picture-uri-dark "'file:///opt/odoo/wallpapers/odoo-wallpaper-tips-dark.png'"'



sleep 30

reboot
