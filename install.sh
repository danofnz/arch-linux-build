#!/usr/bin/env bash
# Arch Linux installer: GNOME on Wayland (GDM), LUKS2 full-disk encryption,
# optional TPM2 auto-unlock. Run as root from the Arch live ISO (UEFI).
# WARNING: wipes the target disk.
set -euo pipefail

die() { echo "error: $*" >&2; exit 1; }
ask() { local v; read -rp "$1" v; echo "${v:-$2}"; }
askpw() { local a b; while :; do
    read -rsp "$1: " a; echo >&2; read -rsp "Confirm: " b; echo >&2
    [[ -n "$a" && "$a" == "$b" ]] && { echo "$a"; return; }
    echo "Passwords empty or do not match." >&2; done; }

[[ $EUID -eq 0 ]] || die "run as root"
[[ -d /sys/firmware/efi/efivars ]] || die "UEFI boot mode required"
SETUP_MODE_VAR="$(find /sys/firmware/efi/efivars -maxdepth 1 -name 'SetupMode-*' -print -quit)"
[[ -n "$SETUP_MODE_VAR" ]] || die "cannot read UEFI Secure Boot setup mode"
SETUP_MODE="$(od -An -j4 -N1 -tu1 "$SETUP_MODE_VAR" | tr -d '[:space:]')"
[[ "$SETUP_MODE" == 1 ]] || die "enter Secure Boot Setup Mode in firmware (clear Secure Boot keys) before installing"

# --- Prompts ---
while :; do
    HOSTNAME_NEW="$(ask 'Hostname [archgnome]: ' archgnome)"
    [[ "$HOSTNAME_NEW" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$ ]] && break
    echo "Invalid hostname."
done
while :; do
    USERNAME_NEW="$(ask 'Username: ' '')"
    [[ "$USERNAME_NEW" =~ ^[a-z_][a-z0-9_-]{0,30}$ && "$USERNAME_NEW" != root ]] && break
    echo "Invalid username (lowercase letters, digits, _ and -; not root)."
done
while :; do
    TIMEZONE="$(ask 'Timezone [Pacific/Auckland]: ' Pacific/Auckland)"
    [[ -e "/usr/share/zoneinfo/$TIMEZONE" && -f "/usr/share/zoneinfo/$TIMEZONE" ]] && break
    echo "Unknown timezone (see /usr/share/zoneinfo)."
done
while :; do
    LOCALE="$(ask 'Locale [en_NZ.UTF-8]: ' en_NZ.UTF-8)"
    grep -q "^#\?${LOCALE//./\.} " /usr/share/i18n/SUPPORTED && break
    echo "Unsupported locale (see /usr/share/i18n/SUPPORTED)."
done
while :; do
    KEYMAP="$(ask 'Keymap [us]: ' us)"
    localectl list-keymaps 2>/dev/null | grep -qx "$KEYMAP" && break
    echo "Unknown keymap (see localectl list-keymaps)."
done
USER_PW="$(askpw "Password for $USERNAME_NEW (administer via sudo)")"
LUKS_PW="$(askpw 'LUKS disk encryption passphrase')"

lsblk -dpno NAME,SIZE,MODEL
DISK="$(ask 'Target disk (device path or name, e.g. /dev/sda or sda): ' '')"
[[ "$DISK" == /* ]] || DISK="/dev/$DISK"
DISK_INPUT="$DISK"
DISK="$(readlink -e -- "$DISK_INPUT" 2>/dev/null)" || die "disk '$DISK_INPUT' does not exist or cannot be resolved"
[[ -b "$DISK" ]] || die "disk '$DISK' is not a block device; choose one of the disks listed above"
DISK_TYPE="$(lsblk -dnro TYPE -- "$DISK" 2>/dev/null || true)"
[[ "$DISK_TYPE" == disk ]] || die "'$DISK' is not a whole disk; select a disk, not a partition"

SPLIT="$(ask 'Split disk into separate encrypted root and /home? [y/N]: ' n)"
ROOT_SIZE=""
if [[ "${SPLIT,,}" == y* ]]; then
    ROOT_SIZE="$(ask 'Root partition size (e.g. 50G): ' 50G)"
    [[ "$ROOT_SIZE" =~ ^[0-9]+[KMGT]$ ]] || die "invalid size"
fi

read -rp "ALL DATA on $DISK will be erased. Type 'yes' to continue: " ok
[[ "$ok" == "yes" ]] || die "aborted"

timedatectl set-ntp true

# --- Partition ---
sgdisk --zap-all "$DISK"
sgdisk -n1:0:+1G -t1:ef00 -c1:ESP "$DISK"
if [[ -n "$ROOT_SIZE" ]]; then
    sgdisk -n2:0:+"$ROOT_SIZE" -t2:8304 -c2:cryptroot "$DISK"
    sgdisk -n3:0:0 -t3:8302 -c3:crypthome "$DISK"
else
    sgdisk -n2:0:0 -t2:8304 -c2:cryptroot "$DISK"
fi
partprobe "$DISK"; sleep 2
if [[ "$DISK" =~ [0-9]$ ]]; then P="${DISK}p"; else P="$DISK"; fi
ESP="${P}1"; ROOTP="${P}2"; HOMEP="${P}3"

# --- LUKS2 ---
luks_setup() { # dev name
    printf '%s' "$LUKS_PW" | cryptsetup luksFormat --type luks2 -q --key-file=- "$1"
    printf '%s' "$LUKS_PW" | cryptsetup open --key-file=- "$1" "$2"
}
luks_setup "$ROOTP" cryptroot
mkfs.ext4 -F /dev/mapper/cryptroot
mount /dev/mapper/cryptroot /mnt
if [[ -n "$ROOT_SIZE" ]]; then
    luks_setup "$HOMEP" crypthome
    mkfs.ext4 -F /dev/mapper/crypthome
    mount --mkdir /dev/mapper/crypthome /mnt/home
fi
mkfs.fat -F32 "$ESP"
mount --mkdir "$ESP" /mnt/boot

# --- Packages ---
UCODE=""
grep -qi GenuineIntel /proc/cpuinfo && UCODE=intel-ucode
grep -qi AuthenticAMD /proc/cpuinfo && UCODE=amd-ucode
pacstrap -K /mnt base linux linux-firmware sudo networkmanager cryptsetup \
    tpm2-tss tpm2-tools sbctl \
    gnome gnome-tweaks gdm xdg-desktop-portal-gnome pipewire wireplumber \
    pipewire-pulse xorg-xwayland qt5-wayland qt6-wayland $UCODE

genfstab -U /mnt >> /mnt/etc/fstab

ROOT_UUID="$(blkid -s UUID -o value "$ROOTP")"
CMDLINE="rd.luks.name=${ROOT_UUID}=cryptroot root=/dev/mapper/cryptroot rw"
if [[ -n "$ROOT_SIZE" ]]; then
    HOME_UUID="$(blkid -s UUID -o value "$HOMEP")"
    CMDLINE="rd.luks.name=${HOME_UUID}=crypthome $CMDLINE"
fi
[[ -n "$UCODE" ]] && INITRD_UCODE="initrd  /${UCODE}.img"

# Passwords are passed via files, not interpolated into the script
printf '%s:%s\n' "$USERNAME_NEW" "$USER_PW" > /mnt/root/.pw
chmod 600 /mnt/root/.pw

arch-chroot /mnt /bin/bash -euo pipefail <<CHROOT
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc
sed -i "s/^#$LOCALE/$LOCALE/" /etc/locale.gen
locale-gen
echo "LANG=$LOCALE" > /etc/locale.conf
echo "KEYMAP=$KEYMAP" > /etc/vconsole.conf
echo "$HOSTNAME_NEW" > /etc/hostname

# systemd-based initramfs: supports rd.luks.name and TPM2 unlock
sed -i 's/^HOOKS=.*/HOOKS=(base systemd autodetect microcode modconf kms keyboard sd-vconsole block sd-encrypt filesystems fsck)/' /etc/mkinitcpio.conf
mkinitcpio -P

bootctl install
cat > /boot/loader/loader.conf <<LOADER
default arch.conf
timeout 3
editor no
LOADER
cat > /boot/loader/entries/arch.conf <<ENTRY
title   Arch Linux
linux   /vmlinuz-linux
${INITRD_UCODE:-}
initrd  /initramfs-linux.img
options $CMDLINE
ENTRY

# Enroll custom keys and sign the boot chain. Secure Boot must be enabled in
# firmware after rebooting; the installer cannot change firmware settings.
sbctl create-keys
sbctl enroll-keys --microsoft --yes-this-might-brick-my-machine
sbctl sign -s /boot/EFI/systemd/systemd-bootx64.efi
sbctl sign -s /boot/EFI/BOOT/BOOTX64.EFI
sbctl sign -s /boot/vmlinuz-linux

# Non-root user; admin rights only via sudo (wheel group, password required)
useradd -m -G wheel -s /bin/bash "$USERNAME_NEW"
chpasswd < /root/.pw
rm -f /root/.pw
passwd -l root
echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/10-wheel
chmod 440 /etc/sudoers.d/10-wheel

rm -f /etc/udev/rules.d/61-gdm.rules
systemctl enable gdm NetworkManager systemd-resolved
CHROOT
rm -f /mnt/root/.pw

umount -R /mnt
cryptsetup close crypthome 2>/dev/null || true
cryptsetup close cryptroot || true
echo "Done. Enable Secure Boot in firmware, then reboot and log in as $USERNAME_NEW."
echo "After Secure Boot is enabled, optional TPM2 enrollment for automatic unlock:"
echo "  systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 $ROOTP"
if [[ -n "$ROOT_SIZE" ]]; then
    echo "  systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 $HOMEP"
fi
