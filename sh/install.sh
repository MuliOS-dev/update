#!/usr/bin/env bash

# install.sh — installs MuliOS Arch kernel packages shipped alongside this
# script. Kernel headers are installed before the kernel package.
#
# Expected layout:
#
# sh/install.sh
# linux-headers-*.pkg.tar.zst
# linux-mulios-*.pkg.tar.zst
# linux-image-*.pkg.tar.zst
# *.pkg.tar.zst
#
# Called by MUpdate as:
#
# ./install.sh
#
# The script can also be run standalone from inside sh/.
#
# Arch Linux / pacman / GRUB systems only.
#
# Version: a1.0.1

set -Eeuo pipefail

# ---------- Terminal helpers ----------

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

# ---------- 1. Privilege / dependency checks ----------

[ "$(id -u)" -eq 0 ] || die "install.sh must be run as root."

command -v pacman >/dev/null 2>&1 \
    || die "pacman not found — this script targets Arch Linux."

command -v grub-mkconfig >/dev/null 2>&1 \
    || die "grub-mkconfig not found — is GRUB installed?"

command -v uname >/dev/null 2>&1 \
    || die "uname not found."

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"

# ---------- 2. Verify this is an Arch-based MuliOS system ----------

if [ -f /etc/os-release ]; then
    . /etc/os-release

    if [[ "${ID:-}" != "arch" && "${ID:-}" != "mulios" ]]; then
        die "This does not appear to be an Arch-based system (ID=${ID:-unknown})."
    fi

    if [[ "${ID:-}" == "mulios" && -n "${ID_LIKE:-}" ]]; then
        if ! echo "$ID_LIKE" | grep -qi "arch"; then
            die "MuliOS does not appear to be Arch-based (ID_LIKE=${ID_LIKE})."
        fi
    fi
fi

ok "Arch-based MuliOS system detected."

# ---------- 3. Find kernel packages ----------

HEADER_PKGS=()
KERNEL_PKGS=()
OTHER_PKGS=()

# Arch package extensions:
#
# .pkg.tar.zst
# .pkg.tar.xz
# .pkg.tar.gz
#
# Explicit package arguments are supported.

if [ "$#" -gt 0 ]; then
    for pkg in "$@"; do
        [ -f "$pkg" ] || die "Package does not exist: $pkg"

        case "$pkg" in
            *-headers-*.pkg.tar.*)
                HEADER_PKGS+=("$(readlink -f "$pkg")")
                ;;
            *)
                KERNEL_PKGS+=("$(readlink -f "$pkg")")
                ;;
        esac
    done
else
    while IFS= read -r -d '' pkg; do
        HEADER_PKGS+=("$pkg")
    done < <(
        find "$PARENT_DIR" \
            -maxdepth 1 \
            -type f \
            \( \
                -iname '*-headers-*.pkg.tar.zst' \
                -o -iname '*-headers-*.pkg.tar.xz' \
                -o -iname '*-headers-*.pkg.tar.gz' \
            \) \
            -print0
    )

    while IFS= read -r -d '' pkg; do
        KERNEL_PKGS+=("$pkg")
    done < <(
        find "$PARENT_DIR" \
            -maxdepth 1 \
            -type f \
            \( \
                -iname '*.pkg.tar.zst' \
                -o -iname '*.pkg.tar.xz' \
                -o -iname '*.pkg.tar.gz' \
            \) \
            ! -iname '*-headers-*.pkg.tar.zst' \
            ! -iname '*-headers-*.pkg.tar.xz' \
            ! -iname '*-headers-*.pkg.tar.gz' \
            -print0
    )
fi

# Sort package lists for deterministic installation.

if [ "${#HEADER_PKGS[@]}" -gt 0 ]; then
    mapfile -t HEADER_PKGS < <(
        printf '%s\n' "${HEADER_PKGS[@]}" | sort
    )
fi

if [ "${#KERNEL_PKGS[@]}" -gt 0 ]; then
    mapfile -t KERNEL_PKGS < <(
        printf '%s\n' "${KERNEL_PKGS[@]}" | sort
    )
fi

ALL_PKGS=(
    "${HEADER_PKGS[@]}"
    "${KERNEL_PKGS[@]}"
)

[ "${#ALL_PKGS[@]}" -gt 0 ] \
    || die "No Arch kernel packages (*.pkg.tar.*) found in $PARENT_DIR."

info "Kernel package(s) to install:"

for pkg in "${ALL_PKGS[@]}"; do
    echo "    - $(basename "$pkg")"
done

# ---------- 4. Record currently-running kernel ----------

OLD_KERNEL="$(uname -r)"

info "Currently running kernel: $OLD_KERNEL"

# Attempt to identify the package providing the currently-running kernel.

OLD_KERNEL_OWNER=""

if command -v pacman >/dev/null 2>&1; then
    for kernel_file in \
        "/usr/lib/modules/${OLD_KERNEL}/vmlinuz" \
        "/boot/vmlinuz-${OLD_KERNEL}" \
        "/boot/vmlinuz-linux"; do

        if [ -e "$kernel_file" ]; then
            OLD_KERNEL_OWNER="$(
                pacman -Qo "$kernel_file" 2>/dev/null |
                awk '{print $5}' |
                head -n1 ||
                true
            )"

            if [ -n "$OLD_KERNEL_OWNER" ]; then
                break
            fi
        fi
    done
fi

if [ -n "$OLD_KERNEL_OWNER" ]; then
    ok "Currently running kernel is provided by package: $OLD_KERNEL_OWNER"
else
    warn "Could not determine the pacman package providing the running kernel."
    warn "The running kernel will not be explicitly removed by this script."
fi

# ---------- 5. Install headers first ----------

if [ "${#HEADER_PKGS[@]}" -gt 0 ]; then
    info "Installing kernel headers first..."

    for pkg in "${HEADER_PKGS[@]}"; do
        info "Installing $(basename "$pkg") ..."
        pacman -U --noconfirm "$pkg" \
            || die "Failed to install $(basename "$pkg")."
    done

    ok "Kernel headers installed."
else
    warn "No kernel headers package found."
fi

# ---------- 6. Install kernel package(s) ----------

if [ "${#KERNEL_PKGS[@]}" -gt 0 ]; then
    info "Installing MuliOS kernel package(s)..."

    for pkg in "${KERNEL_PKGS[@]}"; do
        info "Installing $(basename "$pkg") ..."
        pacman -U --noconfirm "$pkg" \
            || die "Failed to install $(basename "$pkg")."
    done

    ok "MuliOS kernel package(s) installed."
fi

# ---------- 7. Verify installed kernel ----------

info "Checking installed kernel modules..."

NEW_KERNELS=()

if [ -d /usr/lib/modules ]; then
    while IFS= read -r -d '' module_dir; do
        kernel_name="$(basename "$module_dir")"

        # Ignore temporary/backup module directories.
        case "$kernel_name" in
            *.old|*.bak)
                continue
                ;;
        esac

        NEW_KERNELS+=("$kernel_name")
    done < <(
        find /usr/lib/modules \
            -mindepth 1 \
            -maxdepth 1 \
            -type d \
            -print0
    )
fi

if [ "${#NEW_KERNELS[@]}" -gt 0 ]; then
    info "Installed kernel versions:"
    printf '    - %s\n' "${NEW_KERNELS[@]}"
else
    warn "Could not find any installed kernel module directories."
fi

# ---------- 8. Keep currently-running kernel as fallback ----------

if [ -n "$OLD_KERNEL_OWNER" ]; then
    if pacman -Q "$OLD_KERNEL_OWNER" >/dev/null 2>&1; then
        ok "Fallback kernel remains installed: $OLD_KERNEL_OWNER"
    else
        warn "The running kernel package is no longer installed: $OLD_KERNEL_OWNER"
        warn "Check your kernel package dependencies before rebooting."
    fi
else
    ok "No removal operation was performed on the running kernel."
fi

# ---------- 9. Regenerate initramfs ----------

if command -v mkinitcpio >/dev/null 2>&1; then
    info "Regenerating initramfs..."

    mkinitcpio -P \
        || die "mkinitcpio failed."

    ok "initramfs regenerated."

elif command -v dracut >/dev/null 2>&1; then
    info "mkinitcpio not found; using dracut..."

    dracut --regenerate-all --force \
        || die "dracut failed."

    ok "initramfs regenerated with dracut."

else
    warn "Neither mkinitcpio nor dracut was found."
    warn "Skipping initramfs regeneration."
fi

# ---------- 10. Regenerate GRUB configuration ----------

GRUB_CONFIG=""

if [ -d /boot/grub ]; then
    GRUB_CONFIG="/boot/grub/grub.cfg"
elif [ -d /boot/efi/EFI/GRUB ]; then
    GRUB_CONFIG="/boot/efi/EFI/GRUB/grub.cfg"
fi

if [ -z "$GRUB_CONFIG" ]; then
    warn "Could not automatically determine the GRUB configuration path."
    warn "Skipping GRUB configuration regeneration."
else
    info "Regenerating GRUB configuration..."

    grub-mkconfig -o "$GRUB_CONFIG" \
        || die "grub-mkconfig failed."

    ok "GRUB configuration regenerated."
fi

# ---------- 11. Determine newest installed kernel ----------

NEWEST_KERNEL=""

if [ "${#NEW_KERNELS[@]}" -gt 0 ]; then
    NEWEST_KERNEL="$(
        printf '%s\n' "${NEW_KERNELS[@]}" |
        sort -V |
        tail -n1
    )"
fi

echo

ok "MuliOS Arch kernel installation complete."
echo "Report bugs at https://github.com/MuliOS-dev/MUpdate/issues"

echo "Running kernel      : $OLD_KERNEL"

if [ -n "$NEWEST_KERNEL" ]; then
    echo "Newest installed    : $NEWEST_KERNEL"
fi

if [ -n "$OLD_KERNEL_OWNER" ]; then
    echo "Fallback package    : $OLD_KERNEL_OWNER"
else
    echo "Fallback package    : preserved / not identified"
fi

echo "GRUB configuration  : ${GRUB_CONFIG:-not regenerated}"

warn "Reboot to start the newly installed kernel:"
echo "    sudo reboot"
echo
warn "The currently running kernel remains available as a fallback."
echo