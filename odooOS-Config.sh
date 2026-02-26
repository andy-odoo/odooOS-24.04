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

#Block kernel 6.17 on ThinkPad L14 Gen 6 only (known freeze issue)

PREF_FILE="/etc/apt/preferences.d/block-kernel-617"
PRODUCT_VERSION=$(cat /sys/class/dmi/id/product_version 2>/dev/null)

if echo "$PRODUCT_VERSION" | grep -q "ThinkPad L14 Gen 6"; then
    if [ ! -f "$PREF_FILE" ]; then
        echo "ThinkPad L14 Gen 6 detected. Blocking kernel 6.17..."
        tee "$PREF_FILE" > /dev/null <<EOF
Package: linux-*6.17*
Pin: release *
Pin-Priority: -1
EOF
        echo "Kernel 6.17 blocked."
    else
        echo "Kernel 6.17 block already in place. Skipping."
    fi
else
    echo "Model is '$PRODUCT_VERSION' - not a ThinkPad L14 Gen 6. Skipping kernel 6.17 block."
fi


# ── Network connectivity ─────────────────────────────────────────────────
# Skip WiFi if ethernet is already up, otherwise connect to company WiFi

WIFI_SSID="Odoo-SF"
TIMEOUT=30

echo "Checking network connectivity..."
echo "Enter WiFi password for $WIFI_SSID:"
read -rs WIFI_PASS
echo

# Check if any ethernet interface already has a connection
ETH_UP=0
for iface in $(ls /sys/class/net/ | grep -E '^e'); do
    if [ "$(cat /sys/class/net/$iface/operstate 2>/dev/null)" = "up" ]; then
        ETH_UP=1
        echo "Ethernet interface $iface is up — skipping WiFi."
        break
    fi
done

if [ "$ETH_UP" -eq 0 ]; then
    echo "No ethernet detected. Connecting to WiFi: $WIFI_SSID..."

    # Connect via nmcli
    nmcli dev wifi connect "$WIFI_SSID" password "$WIFI_PASS" 2>/dev/null

    # Wait for connectivity with timeout
    echo "Waiting for network (timeout: ${TIMEOUT}s)..."
    ELAPSED=0
    while ! ping -c 1 -W 2 8.8.8.8 &>/dev/null; do
        sleep 2
        ELAPSED=$((ELAPSED + 2))
        if [ "$ELAPSED" -ge "$TIMEOUT" ]; then
            echo ""
            echo "ERROR: Could not connect to $WIFI_SSID after ${TIMEOUT}s."
            echo "Please check the SSID, password, and network availability, then re-run the script."
            exit 1
        fi
        echo "  Still waiting... (${ELAPSED}s)"
    done
    echo "WiFi connected successfully."
else
    # Verify ethernet actually has internet
    if ! ping -c 1 -W 2 8.8.8.8 &>/dev/null; then
        echo "ERROR: Ethernet is up but no internet connectivity detected."
        echo "Please check the network connection and re-run the script."
        exit 1
    fi
    echo "Internet connectivity confirmed."
fi

#Change updates mirror

sed -i -e s,http://be.archive.ubuntu.com/ubuntu/,http://us.archive.ubuntu.com/ubuntu/,g /etc/apt/sources.list.d/ubuntu.sources

#Remove Canon Drivers

dpkg -P cnrdrvcups-ufr2-uk

#Stop packagekitd

systemctl stop packagekit.service

#Stop unattended-upgrades

systemctl stop unattended-upgrades.service

sleep 30

#Remove snap store

snap remove snap-store

#Uninstall deb apps

for f in `cat ./uninstall-deb-apps.txt` ; do apt remove -y $f ; done

#Remove old or invalid deb repos

rm -rf /etc/apt/sources.list.d/*.save
rm -rf /etc/apt/sources.list.d/archive_uri-http_us_archive_ubuntu_com_ubuntu-noble.list

#Add VSCode apt repository

wget -qO /tmp/microsoft.asc https://packages.microsoft.com/keys/microsoft.asc
if [ ! -s /tmp/microsoft.asc ]; then
    echo "ERROR: Failed to download Microsoft GPG key. Skipping VSCode repo."
else
    gpg --dearmor < /tmp/microsoft.asc > /usr/share/keyrings/microsoft.gpg
    chmod 644 /usr/share/keyrings/microsoft.gpg
    rm -f /tmp/microsoft.asc
    cat > /etc/apt/sources.list.d/vscode.sources << 'VSEOF'
Types: deb
URIs: https://packages.microsoft.com/repos/code
Suites: stable
Components: main
Architectures: amd64 arm64 armhf
Signed-By: /usr/share/keyrings/microsoft.gpg
VSEOF
    echo "VSCode repository configured."
fi

#Add Warp Terminal apt repository

wget -qO /tmp/warp.asc https://releases.warp.dev/linux/keys/warp.asc
if [ ! -s /tmp/warp.asc ]; then
    echo "ERROR: Failed to download Warp GPG key. Skipping Warp repo."
else
    gpg --dearmor < /tmp/warp.asc > /etc/apt/keyrings/warpdotdev.gpg
    chmod 644 /etc/apt/keyrings/warpdotdev.gpg
    rm -f /tmp/warp.asc
    echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/warpdotdev.gpg] https://releases.warp.dev/linux/deb stable main"         > /etc/apt/sources.list.d/warpdotdev.list
    echo "Warp Terminal repository configured."
fi

#Add Firefox repo (Mozilla official APT — not Snap)
# packages.mozilla.org serves Firefox only

# Remove Firefox snap stub if present
snap remove firefox 2>/dev/null || true

# Block Ubuntu's Firefox snap stub via apt pin
cat > /etc/apt/preferences.d/no-snap-firefox << 'PINEOF'
Package: firefox
Pin: release o=Ubuntu
Pin-Priority: -1
PINEOF

install -d -m 0755 /etc/apt/keyrings
wget -qO /tmp/mozilla-repo-signing-key.gpg https://packages.mozilla.org/apt/repo-signing-key.gpg
if [ ! -s /tmp/mozilla-repo-signing-key.gpg ]; then
    echo "ERROR: Failed to download Mozilla GPG key. Skipping Firefox repo."
else
    gpg --dearmor < /tmp/mozilla-repo-signing-key.gpg > /etc/apt/keyrings/packages.mozilla.org.gpg
    chmod 644 /etc/apt/keyrings/packages.mozilla.org.gpg
    rm -f /tmp/mozilla-repo-signing-key.gpg
    echo "deb [signed-by=/etc/apt/keyrings/packages.mozilla.org.gpg] https://packages.mozilla.org/apt mozilla main" \
        > /etc/apt/sources.list.d/mozilla.list
    cat > /etc/apt/preferences.d/mozilla << 'MOZEOF'
Package: *
Pin: origin packages.mozilla.org
Pin-Priority: 1001
MOZEOF
    echo "Firefox (Mozilla APT) repository configured."
fi

# Remove Thunderbird snap stub if present (Thunderbird installed via Flatpak instead)
snap remove thunderbird 2>/dev/null || true

#Add Brave browser deb repository

curl -fsSL -o /tmp/brave-keyring.gpg     https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg
if [ ! -s /tmp/brave-keyring.gpg ]; then
    echo "ERROR: Failed to download Brave GPG key. Skipping Brave repo."
else
    cp /tmp/brave-keyring.gpg /usr/share/keyrings/brave-browser-archive-keyring.gpg
    chmod 644 /usr/share/keyrings/brave-browser-archive-keyring.gpg
    rm -f /tmp/brave-keyring.gpg
    curl -fsSL -o /etc/apt/sources.list.d/brave-browser-release.sources         https://brave-browser-apt-release.s3.brave.com/brave-browser.sources
    if [ ! -s /etc/apt/sources.list.d/brave-browser-release.sources ]; then
        echo "ERROR: Failed to download Brave sources file. Skipping Brave repo."
    else
        echo "Brave browser repository configured."
    fi
fi

#Install New deb packages

apt update && apt upgrade -y && apt autoremove -y

#Balena Etcher (download latest release directly from GitHub)

ETCHER_VERSION=$(curl -s https://api.github.com/repos/balena-io/etcher/releases/latest | grep -oP '"tag_name": "\K[^"]+' | tr -d 'v')

if [ -z "$ETCHER_VERSION" ]; then
    echo "WARNING: Could not determine latest Etcher version. Skipping Etcher install."
else
    echo "Installing Balena Etcher v${ETCHER_VERSION}..."
    wget -q "https://github.com/balena-io/etcher/releases/download/v${ETCHER_VERSION}/balena-etcher_${ETCHER_VERSION}_amd64.deb"
    apt install -y ./balena-etcher_${ETCHER_VERSION}_amd64.deb
    rm -f ./balena-etcher_${ETCHER_VERSION}_amd64.deb
    echo "Balena Etcher v${ETCHER_VERSION} installed."
fi

#Remove Google Chrome user confuration

rm -rf /home/odoo/.config/google-chrome

#Remove Google Chrome System Defaults

rm -rf /etc/default/google-chrome

#Apt, update, upgrade and autoremove

apt update && apt --fix-broken install -y && apt upgrade -y
apt autoremove -y

#Install deb packages

for f in `cat ./deb_install.txt` ; do apt install -y $f ; done

#Install flatpaks from USB Drive

flatpak remote-modify --collection-id=org.flathub.Stable flathub
for f in `cat ./flatpaks_install.txt` ; do flatpak install --sideload-repo=./flatpaks/.ostree/repo flathub -y $f ; done

#Manual Flatpak installs

#Zoom

flatpak install -y app/us.zoom.Zoom/x86_64/stable

#Update Flatpaks

flatpak update -y

#Install Touchegg PPA

add-apt-repository -y ppa:touchegg/stable

apt install -y touchegg

#Install touche

flatpak install -y com.github.joseexposito.touche

#Install x11-gestures

sudo -u odoo bash -c 'gnome-extensions install ./x11gesturesjoseexposito.github.io.v25.shell-extension.zip'

sleep 10

#Enable x11-gestures

sudo -u odoo bash -c 'gnome-extensions enable x11gestures@joseexposito.github.io'

#Set Icon Arrangement and settings

sudo -u odoo bash -c 'dconf load / < odoo-gnome-arrangement.txt'

#Set Wallpapers — system-wide default for all users

mkdir -p /usr/share/backgrounds/odoo/
cp ./wallpapers/* /usr/share/backgrounds/odoo/
chmod 644 /usr/share/backgrounds/odoo/*

# Lock wallpaper via dconf system profile — applies to all users including future ones
mkdir -p /etc/dconf/profile
cat > /etc/dconf/profile/user << 'DCONFEOF'
user-db:user
system-db:local
DCONFEOF

mkdir -p /etc/dconf/db/local.d
cat > /etc/dconf/db/local.d/01-odoo-wallpaper << 'DCONFEOF'
[org/gnome/desktop/background]
picture-uri='file:///usr/share/backgrounds/odoo/odoo-wallpaper-tips-light.png'
picture-uri-dark='file:///usr/share/backgrounds/odoo/odoo-wallpaper-tips-dark.png'
picture-options='zoom'

[org/gnome/desktop/screensaver]
picture-uri='file:///usr/share/backgrounds/odoo/odoo-wallpaper-purple.png'
picture-options='zoom'
DCONFEOF

dconf update
echo "System wallpapers installed." 

#Enable fingerprint authentication

apt install -y fprintd libpam-fprintd
pam-auth-update --enable fprintd
echo "Fingerprint authentication enabled."

#Remove gnome keyrings for user odoo

rm -rf /home/odoo/.local/share/keyrings/*

sleep 10

# ── Firmware updates (fwupd) ─────────────────────────────────────────────
echo "Checking for firmware and BIOS updates..."

# Ensure fwupd is installed
if ! command -v fwupdmgr &>/dev/null; then
    apt-get install -y fwupd
fi

# Refresh metadata from LVFS — abort if unreachable
echo "Refreshing firmware metadata from LVFS..."
if ! fwupdmgr refresh --force; then
    echo ""
    echo "ERROR: Could not reach LVFS to check for firmware updates."
    echo "Please verify network connectivity and re-run the script."
    exit 1
fi

# Check for available updates
UPDATES=$(fwupdmgr get-updates 2>&1)
if echo "$UPDATES" | grep -q "No upgrades"; then
    echo "No firmware updates available — continuing."
else
    echo "Firmware updates found. Applying..."
    fwupdmgr update -y --no-reboot-check
    echo ""
    echo "Firmware updates staged. The system may reboot into firmware update"
    echo "mode before booting into the OS — this is normal."
fi


reboot
