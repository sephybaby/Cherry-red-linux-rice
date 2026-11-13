#!/usr/bin/env bash
set -Eeuo pipefail

# Copy selected KDE settings and user-installed theme assets into this repo.
# Existing repository copies are updated. Nothing is deleted from your home.

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_DIR="$HOME/.config"
SHARE_DIR="$HOME/.local/share"
KDE_ROOT="$REPO_ROOT/kde"

mkdir -p "$KDE_ROOT/config"

copy_config_item() {
    local item="$1"
    if [[ -e "$CONFIG_DIR/$item" ]]; then
        cp -a -- "$CONFIG_DIR/$item" "$KDE_ROOT/config/"
        echo "Backed up ~/.config/$item"
    else
        echo "Skipped missing ~/.config/$item"
    fi
}

# Explicitly selected KDE settings. Machine-specific monitor output config,
# SSH host settings, browser profiles, caches and credentials are excluded.
config_items=(
    kdeglobals
    kwinrc
    kglobalshortcutsrc
    konsolerc
    dolphinrc
    krunnerrc
    kscreenlockerrc
    ksplashrc
    ksmserverrc
    kded5rc
    kactivitymanagerdrc
    baloofilerc
    baloo
    kcminputrc
    kcmfonts
    kaccessrc
    kxkbrc
    plasma-localerc
    plasmarc
    plasmashellrc
    plasma-notifyrc
    plasma-welcomerc
    plasma-org.kde.plasma.desktop-appletsrc
    plasma-workspace
    KDE
    kdedefaults
    nothing-kde
    caelestia-kde
    autostart
    gtk-3.0
    gtk-4.0
    Kvantum
)

echo "Backing up selected KDE configuration..."
for item in "${config_items[@]}"; do
    copy_config_item "$item"
done

copy_share_dir() {
    local source="$1"
    local destination="$2"
    if [[ -d "$source" ]]; then
        mkdir -p "$destination"
        cp -a -- "$source/." "$destination/"
        echo "Backed up $source"
    else
        echo "Skipped missing $source"
    fi
}

# User-installed appearance assets. These are copied into descriptive
# repository folders; restore.sh maps them back to their KDE locations.
copy_share_dir "$SHARE_DIR/plasma/desktoptheme" "$KDE_ROOT/plasma-themes"
copy_share_dir "$SHARE_DIR/aurorae/themes" "$KDE_ROOT/window-decorations"
copy_share_dir "$SHARE_DIR/color-schemes" "$KDE_ROOT/color-schemes"
copy_share_dir "$SHARE_DIR/icons" "$KDE_ROOT/icons"
copy_share_dir "$SHARE_DIR/cursors" "$KDE_ROOT/cursors"
copy_share_dir "$SHARE_DIR/konsole" "$KDE_ROOT/konsole"
copy_share_dir "$SHARE_DIR/kwin/scripts" "$KDE_ROOT/kwin-scripts"
copy_share_dir "$SHARE_DIR/plasma/plasmoids" "$KDE_ROOT/widgets"
copy_share_dir "$SHARE_DIR/sounds" "$KDE_ROOT/sounds"
copy_share_dir "$SHARE_DIR/sddm/themes" "$KDE_ROOT/sddm"

# Kvantum themes can also live in ~/.config/Kvantum; the config folder above
# captures those. Do not copy all of ~/.local/share: it contains app data.

echo
echo "Backup complete: $KDE_ROOT"
echo "Review the changes before committing:"
echo "  cd \"$REPO_ROOT\" && git status --short"
echo
echo "Check the copied files for personal information before pushing to GitHub."
