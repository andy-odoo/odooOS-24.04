#!/bin/bash

#Set Wallpapers — system-wide default for all users

read -rp "Enter the username to apply wallpaper settings to: " TARGET_USER
if [ -z "$TARGET_USER" ]; then
    echo "No username provided. Exiting."
    exit 1
fi

# Remove default Ubuntu wallpapers and any user-saved backgrounds
rm -rf /usr/share/backgrounds/*
rm -f /home/${TARGET_USER}/.local/share/backgrounds/*
rm -f /usr/share/gnome-background-properties/ubuntu-wallpapers.xml

mkdir -p /usr/share/backgrounds/odoo/
cp ./wallpapers/* /usr/share/backgrounds/odoo/
chmod 644 /usr/share/backgrounds/odoo/*

# Detect primary screen height to select correct tips wallpaper resolution
SCREEN_HEIGHT=$(cat /sys/class/drm/*/modes 2>/dev/null | grep -oP '^\d+x\K\d+' | sort -rn | head -1)
if [ "$SCREEN_HEIGHT" = "1200" ]; then
    TIPS_LIGHT="odoo-wallpaper-tips-light-1920x1200.png"
    TIPS_DARK="odoo-wallpaper-tips-dark-1920x1200.png"
else
    TIPS_LIGHT="odoo-wallpaper-tips-light-1920x1080.png"
    TIPS_DARK="odoo-wallpaper-tips-dark-1920x1080.png"
fi
echo "Screen height detected: ${SCREEN_HEIGHT}px — using ${TIPS_LIGHT} / ${TIPS_DARK}"

# Lock wallpaper via dconf system profile — applies to all users including future ones
mkdir -p /etc/dconf/profile
cat > /etc/dconf/profile/user << 'DCONFEOF'
user-db:user
system-db:local
DCONFEOF

mkdir -p /etc/dconf/db/local.d
cat > /etc/dconf/db/local.d/01-odoo-wallpaper << DCONFEOF
[org/gnome/desktop/background]
picture-uri='file:///usr/share/backgrounds/odoo/${TIPS_LIGHT}'
picture-uri-dark='file:///usr/share/backgrounds/odoo/${TIPS_DARK}'
picture-options='zoom'

[org/gnome/desktop/screensaver]
picture-uri='file:///usr/share/backgrounds/odoo/odoo-wallpaper-purple.png'
picture-options='zoom'
DCONFEOF

dconf update

# Set wallpaper directly in user's dconf database to override any stale settings
TARGET_UID=$(id -u ${TARGET_USER})
if [ -S "/run/user/${TARGET_UID}/bus" ]; then
    DBUS_ENV="DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/${TARGET_UID}/bus"
else
    DBUS_ENV=""
fi
sudo -u ${TARGET_USER} env ${DBUS_ENV} dconf write /org/gnome/desktop/background/picture-uri "'file:///usr/share/backgrounds/odoo/${TIPS_LIGHT}'"
sudo -u ${TARGET_USER} env ${DBUS_ENV} dconf write /org/gnome/desktop/background/picture-uri-dark "'file:///usr/share/backgrounds/odoo/${TIPS_DARK}'"
sudo -u ${TARGET_USER} env ${DBUS_ENV} dconf write /org/gnome/desktop/background/picture-options "'zoom'"
sudo -u ${TARGET_USER} env ${DBUS_ENV} dconf write /org/gnome/desktop/screensaver/picture-uri "'file:///usr/share/backgrounds/odoo/odoo-wallpaper-purple.png'"
sudo -u ${TARGET_USER} env ${DBUS_ENV} dconf write /org/gnome/desktop/screensaver/picture-options "'zoom'"

# Register wallpapers in GNOME background picker
mkdir -p /usr/share/gnome-background-properties
cat > /usr/share/gnome-background-properties/odoo-wallpapers.xml << XMLEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE wallpapers SYSTEM "gnome-wp-list.dtd">
<wallpapers>
  <wallpaper deleted="false">
    <name>Odoo Tips</name>
    <filename>/usr/share/backgrounds/odoo/${TIPS_LIGHT}</filename>
    <filename-dark>/usr/share/backgrounds/odoo/${TIPS_DARK}</filename-dark>
    <options>zoom</options>
    <shade_type>solid</shade_type>
    <pcolor>#000000</pcolor>
    <scolor>#000000</scolor>
  </wallpaper>
  <wallpaper deleted="false">
    <name>odoo</name>
    <filename>/usr/share/backgrounds/odoo/odoo-wallpaper-notips-light.png</filename>
    <filename-dark>/usr/share/backgrounds/odoo/odoo-wallpaper-notips-dark.png</filename-dark>
    <options>zoom</options>
    <shade_type>solid</shade_type>
    <pcolor>#000000</pcolor>
    <scolor>#000000</scolor>
  </wallpaper>
  <wallpaper deleted="false">
    <name>Odoo Purple</name>
    <filename>/usr/share/backgrounds/odoo/odoo-wallpaper-purple.png</filename>
    <options>zoom</options>
    <shade_type>solid</shade_type>
    <pcolor>#000000</pcolor>
    <scolor>#000000</scolor>
  </wallpaper>
  <wallpaper deleted="false">
    <name>Arches</name>
    <filename>/usr/share/backgrounds/odoo/odoo-wallpaper-arches.jpg</filename>
    <options>zoom</options>
    <shade_type>solid</shade_type>
    <pcolor>#000000</pcolor>
    <scolor>#000000</scolor>
  </wallpaper>
  <wallpaper deleted="false">
    <name>Bryce Canyon</name>
    <filename>/usr/share/backgrounds/odoo/odoo-wallpaper-bryce-canyon.jpg</filename>
    <options>zoom</options>
    <shade_type>solid</shade_type>
    <pcolor>#000000</pcolor>
    <scolor>#000000</scolor>
  </wallpaper>
  <wallpaper deleted="false">
    <name>Rainbow Falls</name>
    <filename>/usr/share/backgrounds/odoo/odoo-wallpaper-rainbow-falls.jpg</filename>
    <options>zoom</options>
    <shade_type>solid</shade_type>
    <pcolor>#000000</pcolor>
    <scolor>#000000</scolor>
  </wallpaper>
  <wallpaper deleted="false">
    <name>Mossbrae Falls</name>
    <filename>/usr/share/backgrounds/odoo/odoo-wallpaper-mossbrae-falls.jpg</filename>
    <options>zoom</options>
    <shade_type>solid</shade_type>
    <pcolor>#000000</pcolor>
    <scolor>#000000</scolor>
  </wallpaper>
  <wallpaper deleted="false">
    <name>Monument Valley</name>
    <filename>/usr/share/backgrounds/odoo/odoo-wallpaper-monument-valley.jpg</filename>
    <options>zoom</options>
    <shade_type>solid</shade_type>
    <pcolor>#000000</pcolor>
    <scolor>#000000</scolor>
  </wallpaper>
  <wallpaper deleted="false">
    <name>Mexican Hat</name>
    <filename>/usr/share/backgrounds/odoo/odoo-wallpaper-mexican-hat.jpg</filename>
    <options>zoom</options>
    <shade_type>solid</shade_type>
    <pcolor>#000000</pcolor>
    <scolor>#000000</scolor>
  </wallpaper>
  <wallpaper deleted="false">
    <name>Yosemite</name>
    <filename>/usr/share/backgrounds/odoo/odoo-wallpaper-yosemite.jpg</filename>
    <options>zoom</options>
    <shade_type>solid</shade_type>
    <pcolor>#000000</pcolor>
    <scolor>#000000</scolor>
  </wallpaper>
  <wallpaper deleted="false">
    <name>Giraffe</name>
    <filename>/usr/share/backgrounds/odoo/odoo-wallpaper-giraffe.jpg</filename>
    <options>zoom</options>
    <shade_type>solid</shade_type>
    <pcolor>#000000</pcolor>
    <scolor>#000000</scolor>
  </wallpaper>
  <wallpaper deleted="false">
    <name>Wild Boar</name>
    <filename>/usr/share/backgrounds/odoo/odoo-wallpaper-wild-boar.jpg</filename>
    <options>zoom</options>
    <shade_type>solid</shade_type>
    <pcolor>#000000</pcolor>
    <scolor>#000000</scolor>
  </wallpaper>
  <wallpaper deleted="false">
    <name>Lion</name>
    <filename>/usr/share/backgrounds/odoo/odoo-wallpaper-lion.jpg</filename>
    <options>zoom</options>
    <shade_type>solid</shade_type>
    <pcolor>#000000</pcolor>
    <scolor>#000000</scolor>
  </wallpaper>
  <wallpaper deleted="false">
    <name>Bison</name>
    <filename>/usr/share/backgrounds/odoo/odoo-wallpaper-bison.jpg</filename>
    <options>zoom</options>
    <shade_type>solid</shade_type>
    <pcolor>#000000</pcolor>
    <scolor>#000000</scolor>
  </wallpaper>
  <wallpaper deleted="false">
    <name>Benjamins</name>
    <filename>/usr/share/backgrounds/odoo/odoo-wallpaper-benjamins.png</filename>
    <options>zoom</options>
    <shade_type>solid</shade_type>
    <pcolor>#000000</pcolor>
    <scolor>#000000</scolor>
  </wallpaper>
  <wallpaper deleted="false">
    <name>Brussels</name>
    <filename>/usr/share/backgrounds/odoo/odoo-wallpaper-brussels.png</filename>
    <options>zoom</options>
    <shade_type>solid</shade_type>
    <pcolor>#000000</pcolor>
    <scolor>#000000</scolor>
  </wallpaper>
  <wallpaper deleted="false">
    <name>San Francisco Night</name>
    <filename>/usr/share/backgrounds/odoo/odoo-wallpaper-san-francisco.png</filename>
    <options>zoom</options>
    <shade_type>solid</shade_type>
    <pcolor>#000000</pcolor>
    <scolor>#000000</scolor>
  </wallpaper>
  <wallpaper deleted="false">
    <name>California Poppies</name>
    <filename>/usr/share/backgrounds/odoo/odoo-wallpaper-california-poppies.png</filename>
    <options>zoom</options>
    <shade_type>solid</shade_type>
    <pcolor>#000000</pcolor>
    <scolor>#000000</scolor>
  </wallpaper>
  <wallpaper deleted="false">
    <name>San Francisco Cloudy</name>
    <filename>/usr/share/backgrounds/odoo/odoo-wallpaper-san-francisco-cloudy.png</filename>
    <options>zoom</options>
    <shade_type>solid</shade_type>
    <pcolor>#000000</pcolor>
    <scolor>#000000</scolor>
  </wallpaper>
  <wallpaper deleted="false">
    <name>Earth 1</name>
    <filename>/usr/share/backgrounds/odoo/odoo-wallpaper-earth-1.jpg</filename>
    <options>zoom</options>
    <shade_type>solid</shade_type>
    <pcolor>#000000</pcolor>
    <scolor>#000000</scolor>
  </wallpaper>
  <wallpaper deleted="false">
    <name>Earth 2</name>
    <filename>/usr/share/backgrounds/odoo/odoo-wallpaper-earth-2.jpg</filename>
    <options>zoom</options>
    <shade_type>solid</shade_type>
    <pcolor>#000000</pcolor>
    <scolor>#000000</scolor>
  </wallpaper>
  <wallpaper deleted="false">
    <name>Earth 3</name>
    <filename>/usr/share/backgrounds/odoo/odoo-wallpaper-earth-3.jpg</filename>
    <options>zoom</options>
    <shade_type>solid</shade_type>
    <pcolor>#000000</pcolor>
    <scolor>#000000</scolor>
  </wallpaper>
  <wallpaper deleted="false">
    <name>Red Rose</name>
    <filename>/usr/share/backgrounds/odoo/odoo-wallpaper-red-rose.jpg</filename>
    <options>zoom</options>
    <shade_type>solid</shade_type>
    <pcolor>#000000</pcolor>
    <scolor>#000000</scolor>
  </wallpaper>
</wallpapers>
XMLEOF
chmod 644 /usr/share/gnome-background-properties/odoo-wallpapers.xml
echo "System wallpapers installed."

