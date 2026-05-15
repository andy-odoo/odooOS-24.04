#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SSD_APT_CACHE="$SCRIPT_DIR/apt-cache"

if [[ $USER != "root" ]]; then
    sudo SCRIPT_DIR="$SCRIPT_DIR" SSD_APT_CACHE="$SSD_APT_CACHE" bash "$SCRIPT_DIR/$(basename "$0")"
    exit 0
fi

exec > >(tee -a "$SCRIPT_DIR/odooOS-26.04-Config.log") 2>&1
echo "=== Script started: $(date) ==="

echo "What is the Employee's First name?"
read employee_first_name
echo "What is the Employee's Gram?"
read employee_gram

chfn -f "$employee_first_name ($employee_gram)" odoo

export DEBIAN_FRONTEND=noninteractive

# ── Network connectivity ─────────────────────────────────────────────────

WIFI_SSID="Odoo-SF"
TIMEOUT=30

echo "Checking network connectivity..."

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
    nmcli dev wifi connect "$WIFI_SSID" password "$WIFI_PASS" 2>/dev/null
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
    if ! ping -c 1 -W 2 8.8.8.8 &>/dev/null; then
        echo "ERROR: Ethernet is up but no internet connectivity detected."
        echo "Please check the network connection and re-run the script."
        exit 1
    fi
    echo "Internet connectivity confirmed."
fi

#Force apt to use IPv4

echo 'Acquire::ForceIPv4 "true";' > /etc/apt/apt.conf.d/99force-ipv4

#Stop packagekitd and unattended-upgrades

systemctl stop packagekit.service
systemctl stop unattended-upgrades.service

echo "Waiting for packagekit and unattended-upgrades to stop..."
while systemctl is-active --quiet packagekit.service; do sleep 1; done
while systemctl is-active --quiet unattended-upgrades.service; do sleep 1; done

#Remove Ubuntu App Center snap and snap Firefox / Thunderbird

snap remove snap-store
snap remove firefox 2>/dev/null || true
snap remove thunderbird 2>/dev/null || true

#Uninstall pre-installed packages not needed on workstations

UNINSTALL_PACKAGES=(
    gnome-snapshot
    shotwell
    transmission-gtk
    totem
    gnome-network-displays
)
for pkg in "${UNINSTALL_PACKAGES[@]}"; do
    apt remove -y "$pkg" 2>/dev/null || true
done

#Get OS codename for repo configuration

. /etc/os-release
OS_CODENAME="${VERSION_CODENAME}"

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

cat > /etc/apt/preferences.d/no-snap-mozilla << 'PINEOF'
Package: firefox
Pin: release o=Ubuntu
Pin-Priority: -1

Package: thunderbird
Pin: release o=Ubuntu
Pin-Priority: -1
PINEOF

add-apt-repository -y ppa:mozillateam/ppa
cat > /etc/apt/preferences.d/mozillateam-ppa << 'PINEOF'
Package: firefox* thunderbird*
Pin: release o=LP-PPA-mozillateam
Pin-Priority: 1001
PINEOF
echo "Mozilla Team PPA (Firefox + Thunderbird) configured."

#Add Brave browser deb repository

curl -fsSL -o /tmp/brave-keyring.gpg \
    https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg
if [ ! -s /tmp/brave-keyring.gpg ]; then
    echo "ERROR: Failed to download Brave GPG key. Skipping Brave repo."
else
    cp /tmp/brave-keyring.gpg /etc/apt/keyrings/brave-browser-archive-keyring.gpg
    chmod 644 /etc/apt/keyrings/brave-browser-archive-keyring.gpg
    rm -f /tmp/brave-keyring.gpg
    curl -fsSL -o /etc/apt/sources.list.d/brave-browser-release.sources \
        https://brave-browser-apt-release.s3.brave.com/brave-browser.sources
    if [ ! -s /etc/apt/sources.list.d/brave-browser-release.sources ]; then
        echo "ERROR: Failed to download Brave sources file. Skipping Brave repo."
    else
        sed -i 's|/usr/share/keyrings/brave-browser-archive-keyring.gpg|/etc/apt/keyrings/brave-browser-archive-keyring.gpg|g' \
            /etc/apt/sources.list.d/brave-browser-release.sources
        echo "Brave browser repository configured."
    fi
fi

#Add Google Chrome apt repository

if curl -fsSL --retry 3 -o /tmp/google-chrome.asc https://dl.google.com/linux/linux_signing_key.pub && \
   gpg --dearmor < /tmp/google-chrome.asc > /usr/share/keyrings/google-chrome.gpg; then
    rm -f /tmp/google-chrome.asc
    chmod 644 /usr/share/keyrings/google-chrome.gpg
    tee /etc/apt/sources.list.d/google-chrome.sources > /dev/null << 'GCEOF'
Types: deb
URIs: https://dl.google.com/linux/chrome/deb/
Suites: stable
Components: main
Architectures: amd64
Signed-By: /usr/share/keyrings/google-chrome.gpg
GCEOF
    echo "Google Chrome repository configured."
else
    rm -f /tmp/google-chrome.asc /usr/share/keyrings/google-chrome.gpg
    echo "ERROR: Failed to set up Google Chrome repository. Skipping."
fi

#Add PostgreSQL apt repository (repo only — server not installed)

install -d /usr/share/postgresql-common/pgdg
curl -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc --fail \
    https://www.postgresql.org/media/keys/ACCC4CF8.asc
if [ ! -s /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc ]; then
    echo "ERROR: Failed to download PostgreSQL GPG key. Skipping PostgreSQL repo."
else
    echo "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] \
https://apt.postgresql.org/pub/repos/apt ${OS_CODENAME}-pgdg main" \
        > /etc/apt/sources.list.d/pgdg.list
    echo "PostgreSQL repository configured."
fi

#Add pgAdmin4 apt repository
# Falls back to noble if 26.04 codename does not have its own pgAdmin4 repo yet

curl -fsS https://www.pgadmin.org/static/packages_pgadmin_org.pub \
    | gpg --dearmor > /etc/apt/keyrings/packages-pgadmin-org.gpg
chmod 644 /etc/apt/keyrings/packages-pgadmin-org.gpg

PGADMIN_CODENAME="${OS_CODENAME}"
if ! curl -fsSL --head \
    "https://ftp.postgresql.org/pub/pgadmin/pgadmin4/apt/${PGADMIN_CODENAME}/dists/pgadmin4/Release" \
    &>/dev/null; then
    echo "pgAdmin4 repo not found for ${PGADMIN_CODENAME}, falling back to noble."
    PGADMIN_CODENAME="noble"
fi

tee /etc/apt/sources.list.d/pgadmin4.sources > /dev/null << PGEOF
Types: deb
URIs: https://ftp.postgresql.org/pub/pgadmin/pgadmin4/apt/${PGADMIN_CODENAME}
Suites: pgadmin4
Components: main
Signed-By: /etc/apt/keyrings/packages-pgadmin-org.gpg
PGEOF
echo "pgAdmin4 repository configured (${PGADMIN_CODENAME})."

#Add NodeSource LTS apt repository (Node.js 22)

curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
    | gpg --dearmor -o /usr/share/keyrings/nodesource.gpg
chmod 644 /usr/share/keyrings/nodesource.gpg
echo "deb [signed-by=/usr/share/keyrings/nodesource.gpg] https://deb.nodesource.com/node_22.x nodistro main" \
    > /etc/apt/sources.list.d/nodesource.list
echo "NodeSource Node.js 22 LTS repository configured."

#Add Neovim PPA (latest stable)

add-apt-repository -y ppa:neovim-ppa/stable

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
      "url": "https://dialpad.com/app",
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

echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/01keep-debs

apt update && apt --fix-broken install -y && apt upgrade -y && apt autoremove -y

DEB_PACKAGES=(
    brave-browser
    flameshot
    audacity
    obs-studio
    darktable
    code
    remmina
    putty
    fprintd
    libpam-fprintd
    dconf-editor
    gnome-shell-extension-caffeine
    gnome-software
    gnome-software-plugin-flatpak
    pgadmin4
    neovim
    nodejs
    sqlitebrowser
    google-chrome-stable
    firefox
    thunderbird
    gnome-chess
    gnome-klotski
    gnome-mahjongg
    gnome-mines
    gnome-robots
    gnome-sudoku
    gnome-taquin
)

for pkg in "${DEB_PACKAGES[@]}"; do
    apt install -y "$pkg"
done

#Override Chrome desktop entry so --password-store=basic is embedded directly in the Exec line
#/etc/default/google-chrome is only used by Chrome for apt repo management, not for passing flags

if [ -f /usr/share/applications/google-chrome.desktop ]; then
    sed -E 's|(Exec=/usr/bin/google-chrome[^ ]*)|\1 --password-store=basic|g' \
        /usr/share/applications/google-chrome.desktop \
        > /home/odoo/.local/share/applications/google-chrome.desktop
    chown odoo:odoo /home/odoo/.local/share/applications/google-chrome.desktop
    echo "Chrome desktop override created with --password-store=basic."
fi

#Sync apt cache back to SSD

mkdir -p "$SSD_APT_CACHE" 2>/dev/null
if [ -d "$SSD_APT_CACHE" ]; then
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

ETCHER_VERSION=$(curl -s https://api.github.com/repos/balena-io/etcher/releases/latest \
    | grep -oP '"tag_name": "\K[^"]+' | tr -d 'v')

if [ -z "$ETCHER_VERSION" ]; then
    echo "WARNING: Could not determine latest Etcher version. Skipping Etcher install."
else
    echo "Installing Balena Etcher v${ETCHER_VERSION}..."
    wget -q --tries=3 "https://github.com/balena-io/etcher/releases/download/v${ETCHER_VERSION}/balena-etcher_${ETCHER_VERSION}_amd64.deb"
    apt install -y ./balena-etcher_${ETCHER_VERSION}_amd64.deb
    rm -f ./balena-etcher_${ETCHER_VERSION}_amd64.deb
    echo "Balena Etcher v${ETCHER_VERSION} installed."
fi

#Remove pre-installed Flatpaks not needed in this deployment

flatpak uninstall -y com.ktechpit.whatsie 2>/dev/null || true

#Install flatpaks from USB Drive

FLATPAK_PACKAGES=(
    com.github.dail8859.NotepadNext
    com.bitwarden.desktop
    com.calibre_ebook.calibre
    com.github.tchx84.Flatseal
    com.vixalien.sticky
    edu.mit.Scratch
    net.scribus.Scribus
    net.xmind.XMind
    org.gimp.GIMP
    org.gnome.Papers
    org.kde.okular
    com.github.jeromerobert.pdfarranger
    org.inkscape.Inkscape
    md.obsidian.Obsidian
    org.openshot.OpenShot
    org.shotcut.Shotcut
    org.kde.kdenlive
    org.strawberrymusicplayer.strawberry
    org.telegram.desktop
    org.ferdium.Ferdium
    us.zoom.Zoom
    org.onlyoffice.desktopeditors
)

flatpak remote-modify --collection-id=org.flathub.Stable flathub
for pkg in "${FLATPAK_PACKAGES[@]}"; do
    flatpak install --sideload-repo=./flatpaks/.ostree/repo flathub -y "$pkg"
done

flatpak update -y

#Pre-create PWA desktop entries so dock icons work before Chrome's first run

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

#Download PWA icons

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

download_pwa_icon "hnpfjngllnobngcgfapefoaidbinmjnm" \
    "https://t0.gstatic.com/faviconV2?client=SOCIAL&type=FAVICON&fallback_opts=TYPE,SIZE,URL&url=https://web.whatsapp.com&size=128"
download_pwa_icon "mohkbeamcbmbidacpegilbjjclnbnaml" \
    "https://t0.gstatic.com/faviconV2?client=SOCIAL&type=FAVICON&fallback_opts=TYPE,SIZE,URL&url=https://dialpad.com&size=128"

chown -R odoo:odoo /home/odoo/.local/share/icons
gtk-update-icon-cache -f /home/odoo/.local/share/icons/hicolor 2>/dev/null || true
update-desktop-database /home/odoo/.local/share/applications 2>/dev/null || true
echo "PWA icon download complete."

#Apply GNOME arrangement and settings

sudo -u odoo dconf load / << 'DCONFEOF'
[org/gnome/desktop/app-folders]
folder-children=['Utilities', 'Internet', 'Office', 'Graphics', 'SoundVideo', 'Programming', 'Games']

[org/gnome/desktop/app-folders/folders/Internet]
apps=['firefox.desktop', 'thunderbird.desktop', 'brave-browser.desktop', 'org.ferdium.Ferdium.desktop', 'org.telegram.desktop.desktop', 'us.zoom.Zoom.desktop', 'remmina.desktop', 'putty.desktop', 'com.bitwarden.desktop.desktop']
name='Internet'

[org/gnome/desktop/app-folders/folders/Office]
apps=['org.onlyoffice.desktopeditors.desktop', 'libreoffice-writer.desktop', 'libreoffice-calc.desktop', 'libreoffice-impress.desktop', 'libreoffice-draw.desktop', 'libreoffice-math.desktop', 'libreoffice-base.desktop', 'libreoffice-startcenter.desktop', 'net.scribus.Scribus.desktop', 'net.xmind.XMind.desktop', 'org.kde.okular.desktop', 'com.github.jeromerobert.pdfarranger.desktop', 'md.obsidian.Obsidian.desktop', 'com.calibre_ebook.calibre.desktop', 'com.github.dail8859.NotepadNext.desktop', 'gnome-text-editor.desktop']
name='Office'

[org/gnome/desktop/app-folders/folders/Graphics]
apps=['org.gimp.GIMP.desktop', 'org.darktable.darktable.desktop', 'org.inkscape.Inkscape.desktop', 'net.scribus.Scribus.desktop', 'com.github.jeromerobert.pdfarranger.desktop', 'gnome-font-viewer.desktop', 'org.gnome.Loupe.desktop']
name='Graphics'

[org/gnome/desktop/app-folders/folders/SoundVideo]
apps=['audacity.desktop', 'com.obsproject.Studio.desktop', 'org.shotcut.Shotcut.desktop', 'org.openshot.OpenShot.desktop', 'org.kde.kdenlive.desktop', 'org.strawberrymusicplayer.strawberry.desktop']
name='Sound & Video'

[org/gnome/desktop/app-folders/folders/Programming]
apps=['code.desktop', 'nvim.desktop', 'pgadmin4.desktop', 'sqlitebrowser.desktop', 'edu.mit.Scratch.desktop']
name='Programming'

[org/gnome/desktop/app-folders/folders/Utilities]
apps=['nm-connection-editor.desktop', 'org.gnome.baobab.desktop', 'org.gnome.DiskUtility.desktop', 'org.gnome.Loupe.desktop', 'org.gnome.seahorse.Application.desktop', 'org.gnome.Logs.desktop', 'org.gnome.Characters.desktop', 'org.gnome.font-viewer.desktop', 'org.gnome.DejaDup.desktop', 'com.github.tchx84.Flatseal.desktop', 'ca.desrt.dconf-editor.desktop', 'balena-etcher.desktop']
categories=['X-GNOME-Utilities']
name='X-GNOME-Utilities.directory'
translate=true

[org/gnome/desktop/app-folders/folders/Games]
apps=['org.gnome.Chess.desktop', 'org.gnome.Klotski.desktop', 'org.gnome.Mahjongg.desktop', 'org.gnome.Mines.desktop', 'org.gnome.Robots.desktop', 'org.gnome.Sudoku.desktop', 'org.gnome.Taquin.desktop']
name='Games'


[org/gnome/desktop/interface]
clock-format='12h'
color-scheme='default'
gtk-theme='Yaru-purple'
icon-theme='Yaru-purple'

[org/gnome/desktop/input-sources]
sources=[('xkb', 'us')]

[org/gnome/desktop/media-handling]
automount=true
automount-open=false

[org/gnome/desktop/privacy]
old-files-age=uint32 30
recent-files-max-age=-1
report-technical-problems=false

[org/gnome/desktop/session]
idle-delay=uint32 300

[org/gnome/nautilus/preferences]
default-folder-viewer='icon-view'
migrated-gtk-settings=true
search-filter-time-type='last_modified'

[org/gnome/settings-daemon/plugins/media-keys]
custom-keybindings=['/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/']

[org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0]
binding='Print'
command='script --command "flameshot gui" /dev/null'
name='flameshot'

[org/gnome/shell/keybindings]
show-screenshot-ui=['Launch2']

[org/gnome/shell]
disabled-extensions=['snapd-prompting@canonical.com', 'snapd-search-provider@canonical.com', 'web-search-provider@ubuntu.com']
enabled-extensions=['ding@rastersoft.com', 'ubuntu-dock@ubuntu.com', 'ubuntu-appindicators@ubuntu.com', 'tiling-assistant@ubuntu.com', 'caffeine@patapon.info']
favorite-apps=['org.gnome.Ptyxis.desktop', 'org.gnome.Nautilus.desktop', 'google-chrome.desktop', 'brave-browser.desktop', 'chrome-mohkbeamcbmbidacpegilbjjclnbnaml-Default.desktop', 'chrome-hnpfjngllnobngcgfapefoaidbinmjnm-Default.desktop', 'org.onlyoffice.desktopeditors.desktop', 'com.vixalien.sticky.desktop', 'flameshot.desktop', 'org.gnome.Software.desktop', 'update-manager.desktop']

[org/gnome/shell/extensions/caffeine]
cli-toggle=false
indicator-position-max=1

[org/gnome/shell/extensions/dash-to-dock]
background-opacity=0.80000000000000004
dash-max-icon-size=48
dock-fixed=false
dock-position='BOTTOM'
height-fraction=0.90000000000000002
intellihide-mode='ALL_WINDOWS'
preferred-monitor=-2
preferred-monitor-by-connector='eDP'

[org/gnome/shell/extensions/ding]
check-x11wayland=true

[org/gnome/shell/extensions/tiling-assistant]
focus-hint-color='rgb(203,67,20)'
last-version-installed=54

[org/gnome/shell/weather]
automatic-location=true
locations=[<(uint32 2, <('San Francisco', 'KOAK', true, [(0.65832848982162007, -2.133408063190589)], [(0.659296885757089, -2.1366218601153339)])>)>]

[org/gnome/shell/world-clocks]
locations=[<(uint32 2, <('San Francisco', 'KOAK', true, [(0.65832848982162007, -2.133408063190589)], [(0.659296885757089, -2.1366218601153339)])>)>, <(uint32 2, <('Brussels', 'EBBR', true, [(0.88837258926511375, 0.079121586939312094)], [(0.88720903061268674, 0.07563092843532343)])>)>, <(uint32 2, <('Mexico City', 'MMMX', true, [(0.33917564548646723, -1.7296212887263802)], [(0.33919020153242879, -1.7302951778038682)])>)>]

[org/gtk/gtk4/settings/file-chooser]
show-hidden=false
sort-directories-first=true

[org/gtk/settings/file-chooser]
clock-format='12h'
show-hidden=false
sort-directories-first=true
DCONFEOF

#Set default file associations

sudo -u odoo xdg-mime default org.gnome.Papers.desktop application/pdf
sudo -u odoo xdg-mime default org.onlyoffice.desktopeditors.desktop application/vnd.openxmlformats-officedocument.wordprocessingml.document
sudo -u odoo xdg-mime default org.onlyoffice.desktopeditors.desktop application/vnd.openxmlformats-officedocument.spreadsheetml.sheet
sudo -u odoo xdg-mime default org.onlyoffice.desktopeditors.desktop application/vnd.openxmlformats-officedocument.presentationml.presentation
sudo -u odoo xdg-mime default org.gnome.TextEditor.desktop text/plain

#Set Wallpapers — system-wide default for all users

rm -rf /usr/share/backgrounds/*
rm -f /home/odoo/.local/share/backgrounds/*
rm -f /usr/share/gnome-background-properties/ubuntu-wallpapers.xml

mkdir -p /usr/share/backgrounds/odoo/
cp ./wallpapers/* /usr/share/backgrounds/odoo/
chmod 644 /usr/share/backgrounds/odoo/*

SCREEN_HEIGHT=$(cat /sys/class/drm/*/modes 2>/dev/null | grep -oP '^\d+x\K\d+' | sort -rn | head -1)
if [ "$SCREEN_HEIGHT" = "1200" ]; then
    TIPS_LIGHT="odoo-wallpaper-tips-light-1920x1200.png"
    TIPS_DARK="odoo-wallpaper-tips-dark-1920x1200.png"
else
    TIPS_LIGHT="odoo-wallpaper-tips-light-1920x1080.png"
    TIPS_DARK="odoo-wallpaper-tips-dark-1920x1080.png"
fi
echo "Screen height detected: ${SCREEN_HEIGHT}px — using ${TIPS_LIGHT} / ${TIPS_DARK}"

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

sudo -u odoo dconf write /org/gnome/desktop/background/picture-uri "'file:///usr/share/backgrounds/odoo/${TIPS_LIGHT}'"
sudo -u odoo dconf write /org/gnome/desktop/background/picture-uri-dark "'file:///usr/share/backgrounds/odoo/${TIPS_DARK}'"
sudo -u odoo dconf write /org/gnome/desktop/background/picture-options "'zoom'"
sudo -u odoo dconf write /org/gnome/desktop/screensaver/picture-uri "'file:///usr/share/backgrounds/odoo/odoo-wallpaper-purple.png'"
sudo -u odoo dconf write /org/gnome/desktop/screensaver/picture-options "'zoom'"

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
  <wallpaper deleted="false">
    <name>Matterhorn</name>
    <filename>/usr/share/backgrounds/odoo/odoo-wallpaper-matterhorn.jpg</filename>
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

#Remove GNOME keyrings for user odoo

rm -rf /home/odoo/.local/share/keyrings/*

# ── Firmware updates (fwupd) ─────────────────────────────────────────────
echo "Checking for firmware and BIOS updates..."

echo "Refreshing firmware metadata from LVFS..."
REFRESH_OUT=$(fwupdmgr refresh --force 2>&1)
echo "$REFRESH_OUT"
if echo "$REFRESH_OUT" | grep -qi "could not"; then
    echo "ERROR: Could not reach LVFS. Please check network and re-run."
    exit 1
fi

SUPPORTED=$(echo "$REFRESH_OUT" | grep -oP '\d+(?= local devices supported)' | head -1)
if [ "${SUPPORTED:-0}" -eq 0 ]; then
    echo "No fwupd-supported devices on this hardware — skipping firmware update."
else
    echo "Applying firmware updates ($SUPPORTED devices supported)..."
    fwupdmgr update -y --no-reboot-check
    echo "Firmware update check complete."
fi

reboot
