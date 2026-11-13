#!/usr/bin/env bash
set -Eeuo pipefail

# Restore the KDE rice from this repository into the current user's home.
# Existing destinations are backed up before being changed.

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
KDE_ROOT="$REPO_ROOT/kde"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_ROOT="$HOME/.local/state/arch-rice-backups/$STAMP"

if [[ ! -d "$KDE_ROOT" ]]; then
    echo "Could not find $KDE_ROOT"
    exit 1
fi

read -r -p "This will apply KDE settings from $KDE_ROOT. Continue? [y/N] " answer
if [[ ! "$answer" =~ ^[Yy]$ ]]; then
    echo "Restore cancelled."
    exit 0
fi

backup_existing() {
    local target="$1"
    if [[ -e "$target" || -L "$target" ]]; then
        local relative="${target#"$HOME"/}"
        mkdir -p "$BACKUP_ROOT/$(dirname "$relative")"
        cp -a -- "$target" "$BACKUP_ROOT/$relative"
    fi
}

restore_config_item() {
    local source="$1"
    local target="$HOME/.config/$(basename "$source")"
    backup_existing "$target"
    mkdir -p "$HOME/.config"
    cp -a -- "$source" "$HOME/.config/"
    echo "Restored ~/.config/$(basename "$source")"
}

if [[ -d "$KDE_ROOT/config" ]]; then
    while IFS= read -r -d '' source; do
        restore_config_item "$source"
    done < <(find "$KDE_ROOT/config" -mindepth 1 -maxdepth 1 -print0)
fi

restore_share_dir() {
    local source="$1"
    local target="$2"
    [[ -d "$source" ]] || return 0
    backup_existing "$target"
    mkdir -p "$target"
    cp -a -- "$source/." "$target/"
    echo "Restored $target"
}

restore_share_dir "$KDE_ROOT/plasma-themes" "$HOME/.local/share/plasma/desktoptheme"
restore_share_dir "$KDE_ROOT/window-decorations" "$HOME/.local/share/aurorae/themes"
restore_share_dir "$KDE_ROOT/color-schemes" "$HOME/.local/share/color-schemes"
restore_share_dir "$KDE_ROOT/icons" "$HOME/.local/share/icons"
restore_share_dir "$KDE_ROOT/cursors" "$HOME/.local/share/cursors"
restore_share_dir "$KDE_ROOT/konsole" "$HOME/.local/share/konsole"
restore_share_dir "$KDE_ROOT/kwin-scripts" "$HOME/.local/share/kwin/scripts"
restore_share_dir "$KDE_ROOT/widgets" "$HOME/.local/share/plasma/plasmoids"
restore_share_dir "$KDE_ROOT/sounds" "$HOME/.local/share/sounds"
restore_share_dir "$KDE_ROOT/sddm" "$HOME/.local/share/sddm/themes"

echo
echo "Restore complete."
if [[ -d "$BACKUP_ROOT" ]]; then
    echo "Previous files were backed up to:"
    echo "  $BACKUP_ROOT"
else
    echo "No existing files needed backing up."
fi
echo
echo "Log out and back in (or restart Plasma) to ensure all settings reload."
