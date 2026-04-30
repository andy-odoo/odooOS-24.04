#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SSD_APT_CACHE="$SCRIPT_DIR/apt-cache"

if [[ $USER != "root" ]]; then
    sudo SCRIPT_DIR="$SCRIPT_DIR" SSD_APT_CACHE="$SSD_APT_CACHE" bash "$SCRIPT_DIR/$(basename "$0")"
    exit 0
fi

# Log all output to file in script directory (stdout + stderr)
exec > >(tee -a "$SCRIPT_DIR/odooOS-Config.log") 2>&1
echo "=== Script started: $(date) ==="

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
    echo "Enter WiFi password for $WIFI_SSID:"
    read -rs WIFI_PASS
    echo
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

#Force apt to use IPv4 (avoids unreachable IPv6 routes on ppa.launchpadcontent.net)

echo 'Acquire::ForceIPv4 "true";' > /etc/apt/apt.conf.d/99force-ipv4

#Change updates mirror

sed -i -e s,http://be.archive.ubuntu.com/ubuntu/,http://us.archive.ubuntu.com/ubuntu/,g /etc/apt/sources.list.d/ubuntu.sources

#Remove Canon Drivers

dpkg -P cnrdrvcups-ufr2-uk

#Remove PostgreSQL (base image ships a full install — not needed on workstations)

apt purge -y postgresql* libpq-dev 2>/dev/null || true
rm -f /etc/apt/sources.list.d/pgdg.list
rm -f /etc/apt/trusted.gpg.d/postgresql*

#Stop packagekitd

systemctl stop packagekit.service

#Stop unattended-upgrades

systemctl stop unattended-upgrades.service

echo "Waiting for packagekit and unattended-upgrades to stop..."
while systemctl is-active --quiet packagekit.service; do sleep 1; done
while systemctl is-active --quiet unattended-upgrades.service; do sleep 1; done

#Remove snap store

snap remove snap-store

#Uninstall deb apps

while IFS= read -r f; do apt remove -y "$f"; done < ./uninstall-deb-apps.txt

#Remove old or invalid deb repos

rm -rf /etc/apt/sources.list.d/*.save
rm -rf /etc/apt/sources.list.d/archive_uri-http_us_archive_ubuntu_com_ubuntu-noble.list
rm -f /etc/apt/sources.list.d/mozilla.list
rm -f /etc/apt/keyrings/packages.mozilla.org.asc \
       /etc/apt/trusted.gpg.d/packages.mozilla.org.gpg

#Add VSCode apt repository

if curl -fsSL --retry 3 -o /tmp/microsoft.asc https://packages.microsoft.com/keys/microsoft.asc && \
   gpg --dearmor < /tmp/microsoft.asc > /usr/share/keyrings/microsoft.gpg; then
    rm -f /tmp/microsoft.asc
    chmod 644 /usr/share/keyrings/microsoft.gpg
    tee /etc/apt/sources.list.d/vscode.sources > /dev/null << 'VSEOF'
Types: deb
URIs: https://packages.microsoft.com/repos/code
Suites: stable
Components: main
Architectures: amd64,arm64,armhf
Signed-By: /usr/share/keyrings/microsoft.gpg
VSEOF
    echo "VSCode repository configured."
else
    rm -f /tmp/microsoft.asc /usr/share/keyrings/microsoft.gpg
    echo "ERROR: Failed to download or dearmor Microsoft GPG key. Skipping VSCode repo."
fi


#Add Mozilla Team PPA (Firefox and Thunderbird — not Snap)

# Remove Firefox and Thunderbird snap stubs if present
snap remove firefox 2>/dev/null || true
snap remove thunderbird 2>/dev/null || true

# Block Ubuntu's snap stubs via apt pin
cat > /etc/apt/preferences.d/no-snap-mozilla << 'PINEOF'
Package: firefox
Pin: release o=Ubuntu
Pin-Priority: -1

Package: thunderbird
Pin: release o=Ubuntu
Pin-Priority: -1
PINEOF

# Add mozillateam PPA and pin it to take priority
add-apt-repository -y ppa:mozillateam/ppa
cat > /etc/apt/preferences.d/mozillateam-ppa << 'PINEOF'
Package: firefox* thunderbird*
Pin: release o=LP-PPA-mozillateam
Pin-Priority: 1001
PINEOF
echo "Mozilla Team PPA (Firefox + Thunderbird) configured."

#Add Brave browser deb repository

curl -fsSL -o /tmp/brave-keyring.gpg     https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg
if [ ! -s /tmp/brave-keyring.gpg ]; then
    echo "ERROR: Failed to download Brave GPG key. Skipping Brave repo."
else
    cp /tmp/brave-keyring.gpg /etc/apt/keyrings/brave-browser-archive-keyring.gpg
    chmod 644 /etc/apt/keyrings/brave-browser-archive-keyring.gpg
    rm -f /tmp/brave-keyring.gpg
    curl -fsSL -o /etc/apt/sources.list.d/brave-browser-release.sources         https://brave-browser-apt-release.s3.brave.com/brave-browser.sources
    if [ ! -s /etc/apt/sources.list.d/brave-browser-release.sources ]; then
        echo "ERROR: Failed to download Brave sources file. Skipping Brave repo."
    else
        # Fix Signed-By path in case Brave sources file points to /usr/share/keyrings
        sed -i 's|/usr/share/keyrings/brave-browser-archive-keyring.gpg|/etc/apt/keyrings/brave-browser-archive-keyring.gpg|g' \
            /etc/apt/sources.list.d/brave-browser-release.sources
        echo "Brave browser repository configured."
    fi
fi

#Add AnyDesk apt repository

if curl -fsSL --retry 3 -o /tmp/anydesk.asc https://keys.anydesk.com/repos/DEB-GPG-KEY && \
   gpg --dearmor < /tmp/anydesk.asc > /etc/apt/keyrings/anydesk.gpg; then
    rm -f /tmp/anydesk.asc
    chmod 644 /etc/apt/keyrings/anydesk.gpg
    tee /etc/apt/sources.list.d/anydesk.sources > /dev/null << 'ADEOF'
Types: deb
URIs: https://deb.anydesk.com
Suites: all
Components: main
Signed-By: /etc/apt/keyrings/anydesk.gpg
ADEOF
    echo "AnyDesk repository configured."
else
    rm -f /tmp/anydesk.asc /etc/apt/keyrings/anydesk.gpg
    echo "ERROR: Failed to download or dearmor AnyDesk GPG key. Skipping AnyDesk repo."
fi

#Add PostgreSQL apt repository (repo only — server not installed)

install -d /usr/share/postgresql-common/pgdg
curl -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc --fail https://www.postgresql.org/media/keys/ACCC4CF8.asc
if [ ! -s /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc ]; then
    echo "ERROR: Failed to download PostgreSQL GPG key. Skipping PostgreSQL repo."
else
    . /etc/os-release
    echo "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] https://apt.postgresql.org/pub/repos/apt $VERSION_CODENAME-pgdg main" > /etc/apt/sources.list.d/pgdg.list
    echo "PostgreSQL repository configured."
fi

#Add pgAdmin4 apt repository

curl -fsS https://www.pgadmin.org/static/packages_pgadmin_org.pub | gpg --dearmor > /etc/apt/keyrings/packages-pgadmin-org.gpg
chmod 644 /etc/apt/keyrings/packages-pgadmin-org.gpg
tee /etc/apt/sources.list.d/pgadmin4.sources > /dev/null << 'PGEOF'
Types: deb
URIs: https://ftp.postgresql.org/pub/pgadmin/pgadmin4/apt/noble
Suites: pgadmin4
Components: main
Signed-By: /etc/apt/keyrings/packages-pgadmin-org.gpg
PGEOF
echo "pgAdmin4 repository configured."

#Add NodeSource LTS apt repository (latest Node.js/NPM)

curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /usr/share/keyrings/nodesource.gpg
chmod 644 /usr/share/keyrings/nodesource.gpg
echo "deb [signed-by=/usr/share/keyrings/nodesource.gpg] https://deb.nodesource.com/node_22.x nodistro main" \
    > /etc/apt/sources.list.d/nodesource.list
echo "NodeSource Node.js 22 LTS repository configured."

#Add LibreOffice PPA (latest stable, replaces distro version)

add-apt-repository -y ppa:libreoffice/ppa

#Add Neovim PPA (latest stable, distro repo is behind)

add-apt-repository -y ppa:neovim-ppa/stable

#Add Touchegg PPA

add-apt-repository -y ppa:touchegg/stable

#Add Darktable PPA

add-apt-repository -y ppa:ubuntuhandbook1/darktable

#Add OBS Studio PPA

add-apt-repository -y ppa:obsproject/obs-studio

#Remove Google Chrome user data and system defaults

rm -rf /home/odoo/.config/google-chrome
rm -rf /home/odoo/.cache/google-chrome
rm -rf /home/odoo/.local/share/google-chrome
rm -rf /etc/opt/chrome/

#Configure Chrome to use basic (unencrypted) password store — bypasses GNOME keyring prompt on first launch

cat > /etc/default/google-chrome << 'EOF'
CHROMIUM_FLAGS="--password-store=basic"
EOF
echo "Chrome password store set to basic."

#Override Chrome desktop entry so --password-store=basic is embedded directly in the Exec line
#/etc/default/google-chrome is only used by Chrome for apt repo management, not for passing flags

if [ -f /usr/share/applications/google-chrome.desktop ]; then
    sed -E 's|(Exec=/usr/bin/google-chrome[^ ]*)|\1 --password-store=basic|g' \
        /usr/share/applications/google-chrome.desktop \
        > /home/odoo/.local/share/applications/google-chrome.desktop
    chown odoo:odoo /home/odoo/.local/share/applications/google-chrome.desktop
    echo "Chrome desktop override created with --password-store=basic."
fi

#Configure Chrome Enterprise policies — force-install PWAs on first launch

mkdir -p /etc/opt/chrome/policies/managed
cat > /etc/opt/chrome/policies/managed/webapps.json << 'EOF'
{
  "WebAppInstallForceList": [
    {
      "url": "https://web.whatsapp.com",
      "default_launch_container": "window",
      "create_desktop_shortcut": false
    },
    {
      "url": "https://dialpad.com",
      "default_launch_container": "window",
      "create_desktop_shortcut": false
    }
  ]
}
EOF
echo "Chrome PWA policy written."

#Restore apt cache from SSD if available

echo "apt cache directory: $SSD_APT_CACHE"
DEB_COUNT=$(ls "$SSD_APT_CACHE"/*.deb 2>/dev/null | wc -l)
echo "SSD apt cache: $DEB_COUNT .deb files found"
if [ -d "$SSD_APT_CACHE" ] && [ "$DEB_COUNT" -gt 0 ]; then
    echo "Restoring apt cache from SSD..."
    cp "$SSD_APT_CACHE"/*.deb /var/cache/apt/archives/ && \
        echo "apt cache restored ($DEB_COUNT files)." || \
        echo "WARNING: apt cache restore failed — packages will be downloaded."
else
    echo "No SSD apt cache found — packages will be downloaded."
fi

#Install deb packages

# Keep downloaded .deb files in cache after install so they can be synced to SSD
# Binary::apt:: prefix is required — plain APT:: does not apply to the apt binary
echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/01keep-debs

apt update && apt --fix-broken install -y && apt upgrade -y && apt autoremove -y

while IFS= read -r f; do apt install -y "$f"; done < ./deb_install.txt

#Sync apt cache back to SSD (done immediately after installs before anything clears the cache)

mkdir -p "$SSD_APT_CACHE" 2>/dev/null
if [ -d "$SSD_APT_CACHE" ]; then
    # Remove outdated versions from SSD cache first, then clean local cache
    apt-get autoclean --dry-run 2>/dev/null | grep ^Del | awk '{print $2}' | \
        xargs -I{} find "$SSD_APT_CACHE" -name "{}*.deb" -delete 2>/dev/null || true
    apt-get autoclean -y
    CACHE_COUNT=$(ls /var/cache/apt/archives/*.deb 2>/dev/null | wc -l)
    echo "Syncing apt cache to SSD ($CACHE_COUNT files)..."
    if [ "$CACHE_COUNT" -gt 0 ]; then
        cp /var/cache/apt/archives/*.deb "$SSD_APT_CACHE"/ && \
            echo "apt cache synced to SSD." || \
            echo "WARNING: Failed to sync apt cache to SSD."
    else
        echo "No .deb files in apt cache to sync."
    fi
else
    echo "WARNING: Could not create apt cache directory on SSD — skipping cache sync."
fi

# Remove keep-packages setting so normal apt behavior resumes on this machine
rm -f /etc/apt/apt.conf.d/01keep-debs

#Install fingerprint driver (ThinkPad E16 Gen 1 only)

PRODUCT_VERSION_FP=$(cat /sys/class/dmi/id/product_name 2>/dev/null)
if echo "$PRODUCT_VERSION_FP" | grep -qE "^21JT|^21JU"; then
    echo "ThinkPad E16 Gen 1 AMD (21JT/21JU) detected. Detecting fingerprint sensor..."
    add-apt-repository -y ppa:libfprint-tod1-group/ppa
    apt update -qq
    if lsusb | grep -q "10a5:9800"; then
        echo "FPC sensor (10a5:9800) detected. Installing FPC fingerprint driver..."
        apt install -y libfprint-2-tod1-fpc
        echo "FPC fingerprint driver installed."
    elif lsusb | grep -q "04f3:0c4b"; then
        echo "ELAN sensor (04f3:0c4b) detected. Installing ELAN fingerprint driver..."
        apt install -y libfprint-2-tod1-elan
        echo "ELAN fingerprint driver installed."
    else
        echo "No known fingerprint sensor detected. Skipping fingerprint driver."
    fi
else
    echo "Model is '$PRODUCT_VERSION_FP' - not a ThinkPad E16 Gen 1. Skipping fingerprint driver."
fi


#Install Google Gemini CLI

npm install -g @google/gemini-cli
echo "Google Gemini CLI installed."

#Install Claude Code

npm install -g @anthropic-ai/claude-code
echo "Claude Code installed."

#Balena Etcher (download latest release directly from GitHub)

ETCHER_VERSION=$(curl -s https://api.github.com/repos/balena-io/etcher/releases/latest | grep -oP '"tag_name": "\K[^"]+' | tr -d 'v')

if [ -z "$ETCHER_VERSION" ]; then
    echo "WARNING: Could not determine latest Etcher version. Skipping Etcher install."
else
    echo "Installing Balena Etcher v${ETCHER_VERSION}..."
    wget -q --tries=3 "https://github.com/balena-io/etcher/releases/download/v${ETCHER_VERSION}/balena-etcher_${ETCHER_VERSION}_amd64.deb"
    apt install -y ./balena-etcher_${ETCHER_VERSION}_amd64.deb
    rm -f ./balena-etcher_${ETCHER_VERSION}_amd64.deb
    echo "Balena Etcher v${ETCHER_VERSION} installed."
fi

#RustDesk (download latest release directly from GitHub)

RUSTDESK_VERSION=$(curl -s https://api.github.com/repos/rustdesk/rustdesk/releases/latest | grep -oP '"tag_name": "\K[^"]+' | tr -d 'v')

if [ -z "$RUSTDESK_VERSION" ]; then
    echo "WARNING: Could not determine latest RustDesk version. Skipping RustDesk install."
else
    echo "Installing RustDesk v${RUSTDESK_VERSION}..."
    wget -q --tries=3 "https://github.com/rustdesk/rustdesk/releases/download/${RUSTDESK_VERSION}/rustdesk-${RUSTDESK_VERSION}-x86_64.deb"
    apt install -y ./rustdesk-${RUSTDESK_VERSION}-x86_64.deb
    rm -f ./rustdesk-${RUSTDESK_VERSION}-x86_64.deb
    echo "RustDesk v${RUSTDESK_VERSION} installed."
fi

#Remove pre-installed Flatpaks not needed in this deployment

flatpak uninstall -y com.ktechpit.whatsie 2>/dev/null || true

#Install flatpaks from USB Drive

flatpak remote-modify --collection-id=org.flathub.Stable flathub
while IFS= read -r f; do flatpak install --sideload-repo=./flatpaks/.ostree/repo flathub -y "$f"; done < ./flatpaks_install.txt

#Update Flatpaks

flatpak update -y

#Install x11-gestures

GNOME_VERSION=$(gnome-shell --version 2>/dev/null | grep -oP '\d+\.\d+' | head -1)
X11G_URL="https://extensions.gnome.org/download-extension/x11gestures@joseexposito.github.io.shell-extension.zip?shell_version=${GNOME_VERSION}"
wget -q --tries=3 -O /tmp/x11gestures.zip "$X11G_URL"
if [ ! -s /tmp/x11gestures.zip ]; then
    echo "WARNING: Could not download x11-gestures for GNOME ${GNOME_VERSION}. Skipping."
else
    sudo -u odoo bash -c 'gnome-extensions install /tmp/x11gestures.zip'
    rm -f /tmp/x11gestures.zip
    echo "Waiting for x11-gestures extension to register..."
    ELAPSED=0
    until sudo -u odoo bash -c 'gnome-extensions list' 2>/dev/null | grep -q 'x11gestures@joseexposito.github.io'; do
        sleep 1
        ELAPSED=$((ELAPSED + 1))
        if [ "$ELAPSED" -ge 30 ]; then
            echo "WARNING: x11-gestures extension did not register within 30s — continuing anyway."
            break
        fi
    done
    sudo -u odoo bash -c 'gnome-extensions enable x11gestures@joseexposito.github.io'
    echo "x11-gestures extension installed and enabled."
fi

#Pre-create WhatsApp Web PWA desktop entry so dock icon works before Chrome's first run

mkdir -p /home/odoo/.local/share/applications
cat > /home/odoo/.local/share/applications/chrome-hnpfjngllnobngcgfapefoaidbinmjnm-Default.desktop << 'EOF'
[Desktop Entry]
Version=1.0
Terminal=false
Type=Application
Name=WhatsApp Web
Exec=/opt/google/chrome/google-chrome --profile-directory=Default --app-id=hnpfjngllnobngcgfapefoaidbinmjnm
Icon=chrome-hnpfjngllnobngcgfapefoaidbinmjnm-Default
StartupWMClass=crx_hnpfjngllnobngcgfapefoaidbinmjnm
EOF
chown odoo:odoo /home/odoo/.local/share/applications/chrome-hnpfjngllnobngcgfapefoaidbinmjnm-Default.desktop
echo "WhatsApp Web desktop entry created."

cat > /home/odoo/.local/share/applications/chrome-mohkbeamcbmbidacpegilbjjclnbnaml-Default.desktop << 'EOF'
[Desktop Entry]
Version=1.0
Terminal=false
Type=Application
Name=Dialpad
MimeType=x-scheme-handler/tel;x-scheme-handler/web+dialpad;x-scheme-handler/google-chrome;
Exec=/opt/google/chrome/google-chrome --profile-directory=Default --app-id=mohkbeamcbmbidacpegilbjjclnbnaml %U
Icon=chrome-mohkbeamcbmbidacpegilbjjclnbnaml-Default
StartupWMClass=crx_mohkbeamcbmbidacpegilbjjclnbnaml
EOF
chown odoo:odoo /home/odoo/.local/share/applications/chrome-mohkbeamcbmbidacpegilbjjclnbnaml-Default.desktop
echo "Dialpad desktop entry created."

#Download PWA icons from known stable CDN URLs
#Manifest-scraping is unreliable: these apps return HTML (not JSON) to curl requests

echo "Downloading PWA icons..."
mkdir -p /home/odoo/.local/share/icons/hicolor/128x128/apps

download_pwa_icon() {
    local app_id="$1"
    local icon_url="$2"
    local icon_out="/home/odoo/.local/share/icons/hicolor/128x128/apps/chrome-${app_id}-Default.png"
    local ua="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"

    curl -sL --max-time 15 -H "User-Agent: $ua" "$icon_url" -o "$icon_out" 2>/dev/null
    [ -s "$icon_out" ] \
        && echo "  Downloaded icon for $app_id" \
        || echo "  Failed to download icon for $app_id"
}

# WhatsApp — Google Favicon API (reliable, no static hash in URL)
download_pwa_icon "hnpfjngllnobngcgfapefoaidbinmjnm" \
    "https://t0.gstatic.com/faviconV2?client=SOCIAL&type=FAVICON&fallback_opts=TYPE,SIZE,URL&url=https://web.whatsapp.com&size=128"
# Dialpad — Google Favicon API
download_pwa_icon "mohkbeamcbmbidacpegilbjjclnbnaml" \
    "https://t0.gstatic.com/faviconV2?client=SOCIAL&type=FAVICON&fallback_opts=TYPE,SIZE,URL&url=https://dialpad.com&size=128"

chown -R odoo:odoo /home/odoo/.local/share/icons
gtk-update-icon-cache -f /home/odoo/.local/share/icons/hicolor 2>/dev/null || true
update-desktop-database /home/odoo/.local/share/applications 2>/dev/null || true
echo "PWA icon download complete."

#Set Icon Arrangement and settings

sudo -u odoo bash -c 'dconf load / < odoo-gnome-arrangement.txt'

#Set GNOME Papers as default PDF handler

sudo -u odoo xdg-mime default org.gnome.Papers.desktop application/pdf
sudo -u odoo xdg-mime default org.onlyoffice.desktopeditors.desktop application/vnd.openxmlformats-officedocument.wordprocessingml.document
sudo -u odoo xdg-mime default org.onlyoffice.desktopeditors.desktop application/vnd.openxmlformats-officedocument.spreadsheetml.sheet
sudo -u odoo xdg-mime default org.onlyoffice.desktopeditors.desktop application/vnd.openxmlformats-officedocument.presentationml.presentation
sudo -u odoo xdg-mime default org.gnome.TextEditor.desktop text/plain

#Set Wallpapers — system-wide default for all users

# Remove default Ubuntu wallpapers and any user-saved backgrounds
rm -rf /usr/share/backgrounds/*
rm -f /home/odoo/.local/share/backgrounds/*
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

# Set wallpaper directly in odoo user's dconf database to override any stale settings
sudo -u odoo dconf write /org/gnome/desktop/background/picture-uri "'file:///usr/share/backgrounds/odoo/${TIPS_LIGHT}'"
sudo -u odoo dconf write /org/gnome/desktop/background/picture-uri-dark "'file:///usr/share/backgrounds/odoo/${TIPS_DARK}'"
sudo -u odoo dconf write /org/gnome/desktop/background/picture-options "'zoom'"
sudo -u odoo dconf write /org/gnome/desktop/screensaver/picture-uri "'file:///usr/share/backgrounds/odoo/odoo-wallpaper-purple.png'"
sudo -u odoo dconf write /org/gnome/desktop/screensaver/picture-options "'zoom'"

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
</wallpapers>
XMLEOF
chmod 644 /usr/share/gnome-background-properties/odoo-wallpapers.xml
echo "System wallpapers installed."  


#Enable fingerprint authentication

pam-auth-update --enable fprintd
echo "Fingerprint authentication enabled."

#Set root password

echo "root:0dooB3\$F!" | chpasswd
echo "Root password set."

#Enable sudo password feedback (show * when typing password)

echo "Defaults pwfeedback" > /etc/sudoers.d/pwfeedback
chmod 440 /etc/sudoers.d/pwfeedback
echo "Sudo password feedback enabled."

#Disable AnyDesk and RustDesk autostart (launch manually when needed)

systemctl disable anydesk.service 2>/dev/null || true
systemctl disable rustdesk.service 2>/dev/null || true
rm -f /etc/xdg/autostart/anydesk.desktop \
       /etc/xdg/autostart/rustdesk.desktop \
       /home/odoo/.config/autostart/anydesk.desktop \
       /home/odoo/.config/autostart/rustdesk.desktop
echo "AnyDesk and RustDesk autostart disabled."

#Remove gnome keyrings for user odoo

rm -rf /home/odoo/.local/share/keyrings/*

# ── Firmware updates (fwupd) ─────────────────────────────────────────────
echo "Checking for firmware and BIOS updates..."

# Refresh metadata from LVFS — abort if unreachable
echo "Refreshing firmware metadata from LVFS..."
REFRESH_OUT=$(fwupdmgr refresh --force 2>&1)
echo "$REFRESH_OUT"
if echo "$REFRESH_OUT" | grep -qi "could not"; then
    echo "ERROR: Could not reach LVFS. Please check network and re-run."
    exit 1
fi

# Skip update if this hardware has no fwupd-supported devices
SUPPORTED=$(echo "$REFRESH_OUT" | grep -oP '\d+(?= local devices supported)' | head -1)
if [ "${SUPPORTED:-0}" -eq 0 ]; then
    echo "No fwupd-supported devices on this hardware — skipping firmware update."
else
    echo "Applying firmware updates ($SUPPORTED devices supported)..."
    fwupdmgr update -y --no-reboot-check
    echo "Firmware update check complete."
fi

reboot
