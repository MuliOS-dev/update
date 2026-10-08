#!/usr/bin/env bash
#
# package.sh — Universal Arch package installer for MuliOS
#
# Usage:
#   ./package.sh package1 package2 package3
#
# Or place package names in packages.txt beside this script:
#   ./package.sh
#
# Blank lines and lines beginning with # are ignored.
#

set -Eeuo pipefail

# ---------- Colors ----------

C_RED=$'\033[0;31m'
C_GRN=$'\033[0;32m'
C_YEL=$'\033[0;33m'
C_BLU=$'\033[0;34m'
C_RST=$'\033[0m'

info() { echo "${C_BLU}==>${C_RST} $*"; }
ok()   { echo "${C_GRN}==>${C_RST} $*"; }
warn() { echo "${C_YEL}==>${C_RST} $*"; }
err()  { echo "${C_RED}==>${C_RST} $*" >&2; }
die()  { err "$*"; exit 1; }

# ---------- Root / dependency checks ----------

[ "$(id -u)" -eq 0 ] || die "package.sh must be run as root."

command -v pacman >/dev/null 2>&1 \
    || die "pacman was not found. This script requires an Arch-based system."

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_LIST="$SCRIPT_DIR/packages.txt"

# ---------- Collect packages ----------

PACKAGES=(
    "7zip"
    "python-pip"
    "pyside6"
    "qt-base"
)

# Packages passed directly to the script.
if [ "$#" -gt 0 ]; then
    PACKAGES+=("$@")
fi

# Also read packages.txt if it exists.
if [ -f "$PACKAGE_LIST" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
        # Remove leading/trailing whitespace.
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"

        # Ignore empty lines and comments.
        [ -z "$line" ] && continue
        [[ "$line" == \#* ]] && continue

        PACKAGES+=("$line")
    done < "$PACKAGE_LIST"
fi

[ "${#PACKAGES[@]}" -gt 0 ] \
    || die "No packages specified. Pass package names or create packages.txt."

# Remove duplicate package names while preserving order.
UNIQUE_PACKAGES=()

for pkg in "${PACKAGES[@]}"; do
    already_seen=false

    for existing in "${UNIQUE_PACKAGES[@]}"; do
        if [ "$existing" = "$pkg" ]; then
            already_seen=true
            break
        fi
    done

    if [ "$already_seen" = false ]; then
        UNIQUE_PACKAGES+=("$pkg")
    fi
done

PACKAGES=("${UNIQUE_PACKAGES[@]}")

# ---------- Show package list ----------

info "Packages requested:"

for pkg in "${PACKAGES[@]}"; do
    echo "    - $pkg"
done

echo

# ---------- Check already-installed packages ----------

TO_INSTALL=()

for pkg in "${PACKAGES[@]}"; do
    if pacman -Q "$pkg" >/dev/null 2>&1; then
        echo "${C_YEL}[-]${C_RST} $pkg is already installed."
    else
        TO_INSTALL+=("$pkg")
    fi
done

# Nothing left to install.
if [ "${#TO_INSTALL[@]}" -eq 0 ]; then
    echo
    ok "All requested packages are already installed."
    exit 0
fi

echo

# ---------- Synchronize package databases ----------

info "Synchronizing package databases..."

pacman -Sy --noconfirm \
    || die "Failed to synchronize package databases."

# ---------- Install packages ----------

info "Installing ${#TO_INSTALL[@]} package(s)..."

if pacman -S --needed --noconfirm "${TO_INSTALL[@]}"; then
    echo
    ok "All requested packages were installed successfully."
else
    echo
    err "One or more packages failed to install."
    exit 1
fi

# ---------- Final verification ----------

echo
info "Verifying installed packages..."

FAILED=()

for pkg in "${PACKAGES[@]}"; do
    if pacman -Q "$pkg" >/dev/null 2>&1; then
        echo "    ${C_GRN}[OK]${C_RST} $pkg"
    else
        echo "    ${C_RED}[FAIL]${C_RST} $pkg"
        FAILED+=("$pkg")
    fi
done

if [ "${#FAILED[@]}" -gt 0 ]; then
    echo
    die "The following packages are not installed: ${FAILED[*]}"
fi

echo
ok "Package installation complete."