#!/usr/bin/env bash
set -Eeuo pipefail

# Install packages listed in packages/pacman.txt and packages/aur.txt.
# Then offer to apply the KDE configuration stored in kde/.
# Run from anywhere: this script locates the repository automatically.

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
PACMAN_LIST="$REPO_ROOT/packages/pacman.txt"
AUR_LIST="$REPO_ROOT/packages/aur.txt"

if [[ ! -f /etc/arch-release ]]; then
    echo "This installer is intended for Arch Linux."
    exit 1
fi

read_packages() {
    local file="$1"
    [[ -f "$file" ]] || return 0
    grep -Ev '^[[:space:]]*(#|$)' "$file" || true
}

mapfile -t pacman_packages < <(read_packages "$PACMAN_LIST")
mapfile -t aur_packages < <(read_packages "$AUR_LIST")

echo "Arch KDE rice installer"
echo "Repository: $REPO_ROOT"
echo

if ((${#pacman_packages[@]})); then
    echo "Official repository packages:"
    printf '  %s\n' "${pacman_packages[@]}"
    echo
    read -r -p "Install these with pacman? [y/N] " answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
        sudo pacman -S --needed -- "${pacman_packages[@]}"
    else
        echo "Skipping pacman packages."
    fi
else
    echo "No packages listed in packages/pacman.txt."
fi

if ((${#aur_packages[@]})); then
    echo
    echo "AUR packages:"
    printf '  %s\n' "${aur_packages[@]}"
    aur_helper=""
    if command -v paru >/dev/null 2>&1; then
        aur_helper="paru"
    elif command -v yay >/dev/null 2>&1; then
        aur_helper="yay"
    fi

    if [[ -z "$aur_helper" ]]; then
        echo "AUR packages are listed, but neither paru nor yay is installed."
        echo "Install an AUR helper yourself, then rerun this script."
    else
        read -r -p "Install these with $aur_helper? [y/N] " answer
        if [[ "$answer" =~ ^[Yy]$ ]]; then
            "$aur_helper" -S --needed -- "${aur_packages[@]}"
        else
            echo "Skipping AUR packages."
        fi
    fi
else
    echo "No packages listed in packages/aur.txt."
fi

echo
read -r -p "Apply this repository's KDE configuration now? [y/N] " answer
if [[ "$answer" =~ ^[Yy]$ ]]; then
    "$REPO_ROOT/scripts/restore.sh"
else
    echo "Packages step finished. You can apply the rice later with:"
    echo "  $REPO_ROOT/scripts/restore.sh"
fi
