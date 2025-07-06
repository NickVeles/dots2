#!/bin/bash

set -e # Exit on any error
set -u # Treat unset variables as error

# Ensure script is run as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run this script as root using sudo"
    exit 1
fi

# Parse flags
NO_BLOAT=false
NO_NVIDIA=false

for arg in "$@"; do
    case $arg in
        --no-bloat)
            NO_BLOAT=true
            ;;
        --no-nvidia)
            NO_NVIDIA=true
            ;;
        *)
            echo "[!] Unknown option: $arg"
            exit 1
            ;;
    esac
done

# Determine the original user
ORIG_USER=$(logname)
ORIG_HOME=$(eval echo "~$ORIG_USER")

echo "[*] Installing dependencies for user: $ORIG_USER"

# Step 1: Install yay if not already installed
if ! command -v yay &>/dev/null; then
    echo "[*] yay not found. Installing yay..."
    sudo -u "$ORIG_USER" bash -c "
        cd /tmp &&
        git clone https://aur.archlinux.org/yay.git &&
        cd yay &&
        makepkg -si --noconfirm
    "
else
    echo "[*] yay already installed."
fi

# Step 2: Install dependencies
if [ -f "pkglist.txt" ]; then
    echo "[*] Installing packages from pkglist.txt..."
    sudo -u "$ORIG_USER" yay -S --noconfirm --needed - < "pkglist.txt"
else
    echo "[!] pkglist.txt not found! Skipping package installation."
fi

if ! $NO_BLOAT; then
    if [ -f "pkglist-optional.txt" ]; then
        echo "[*] Installing packages from pkglist-optional.txt..."
        sudo -u "$ORIG_USER" yay -S --noconfirm --needed - < "pkglist-optional.txt"
    else
        echo "[!] pkglist-optional.txt not found! Skipping package installation."
    fi
fi

# Step 3: Copy dotfiles from ./copy/ to ~
COPY_DIR="./copy"
if [ -d "$COPY_DIR" ]; then
    echo "[*] Copying files from $COPY_DIR to $ORIG_HOME..."
    rsync -a --exclude '.git' "$COPY_DIR"/ "$ORIG_HOME"/
    chown -R "$ORIG_USER:$ORIG_USER" "$ORIG_HOME"
else
    echo "[!] $COPY_DIR not found. Skipping file copy."
fi

# Step 4: Wipe nvidia.conf if --no-nvidia is specified
if [ "$NO_NVIDIA" = true ]; then
    NVIDIA_CONF="$ORIG_HOME/.config/hypr/nvidia.conf"
    if [ -f "$NVIDIA_CONF" ]; then
        echo "[*] Clearing contents of $NVIDIA_CONF (as --no-nvidia was passed)..."
        truncate -s 0 "$NVIDIA_CONF"
        chown "$ORIG_USER:$ORIG_USER" "$NVIDIA_CONF"
    else
        echo "[!] $NVIDIA_CONF not found. Nothing to wipe."
    fi
fi

# Step 5: Enable services - ufw, cups.service
echo "[*] Enabling ufw and cups.service..."
systemctl enable ufw.service
systemctl enable cups.service
echo "[*] Services enabled."

# Step 6: Enable Experimental = true in /etc/bluetooth/main.conf
BT_CONF="/etc/bluetooth/main.conf"
if [ -f "$BT_CONF" ]; then
    echo "[*] Enabling Experimental = true in $BT_CONF..."
    if grep -q "^#*Experimental *= *true" "$BT_CONF"; then
        sed -i 's/^#*Experimental *= *.*/Experimental = true/' "$BT_CONF"
    else
        echo "Experimental = true" >> "$BT_CONF"
    fi
else
    echo "[!] $BT_CONF not found. Skipping Bluetooth config update."
fi

# Step 6: Move sugar-candy theme and sddm.conf
SDDM_THEME_SRC="$ORIG_HOME/sugar-candy"
SDDM_THEME_DEST="/usr/share/sddm/themes/sugar-candy"
SDDM_CONF_SRC="$ORIG_HOME/sddm.conf"
SDDM_CONF_DEST="/etc/sddm.conf"

# Move sugar-candy theme
if [ -d "$SDDM_THEME_SRC" ]; then
    echo "[*] Moving sugar-candy theme to $SDDM_THEME_DEST..."
    mv "$SDDM_THEME_SRC" "$SDDM_THEME_DEST"
else
    echo "[!] Theme folder $SDDM_THEME_SRC not found. Skipping."
fi

# Move sddm.conf
if [ -f "$SDDM_CONF_SRC" ]; then
    echo "[*] Moving sddm.conf to $SDDM_CONF_DEST..."
    mv "$SDDM_CONF_SRC" "$SDDM_CONF_DEST"
else
    echo "[!] Config file $SDDM_CONF_SRC not found. Skipping."
fi

# Step 7: Clone and install Colloid GTK theme
COLLOID_REPO="https://github.com/vinceliuice/Colloid-gtk-theme"
COLLOID_DIR="$ORIG_HOME/Colloid-gtk-theme"

echo "[*] Cloning Colloid GTK theme..."
sudo -u "$ORIG_USER" git clone "$COLLOID_REPO" "$COLLOID_DIR"

if [ -f "$COLLOID_DIR/install.sh" ]; then
    echo "[*] Installing Colloid GTK theme with orange + rimless tweaks..."
    sudo -u "$ORIG_USER" bash "$COLLOID_DIR/install.sh" --theme orange --tweaks rimless
else
    echo "[!] install.sh not found in $COLLOID_DIR. Skipping installation."
fi

echo "[*] Removing Colloid GTK theme source directory..."
rm -rf "$COLLOID_DIR"

# Step 8: Extract wallpapers archive
WALLPAPER_ARCHIVE="$ORIG_HOME/Pictures/Wallpapers/Wallpapers.tar.gz"
WALLPAPER_DEST="$ORIG_HOME/Pictures/Wallpapers"

if [ -f "$WALLPAPER_ARCHIVE" ]; then
    echo "[*] Extracting wallpapers from $WALLPAPER_ARCHIVE..."
    sudo -u "$ORIG_USER" tar -xzf "$WALLPAPER_ARCHIVE" -C "$WALLPAPER_DEST"
else
    echo "[!] Wallpaper archive $WALLPAPER_ARCHIVE not found. Skipping extraction."
fi

echo "[✓] Dotfiles installation complete."