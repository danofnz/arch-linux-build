#!/usr/bin/env bash
# Arch Linux installer: GNOME desktop on Wayland (GDM + GNOME Shell/Mutter).
# Run as root from the Arch live ISO (UEFI boot). WARNING: wipes the target disk.
set -euo pipefail

DISK="${DISK:-}"
HOSTNAME="${HOSTNAME_NEW:-archgnome}"
USERNAME="${USERNAME_NEW:-user}"
TIMEZONE="${TIMEZONE:-UTC}"
LOCALE="${LOCALE:-en_US.UTF-8}"
KEYMAP="${KEYMAP:-us}"

die() { echo "error: $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "run as root"
[[ -d /sys/firmware/efi/efivars ]] || die "UEFI boot mode required"

if [[ -z "$DISK" ]]; then
    lsblk -dpno NAME,SIZE,MODEL
    read -rp "Target disk (e.g. /dev/sda): " DISK
fi
[[ -b "$DISK" ]] || die "$DISK is not a block device"

read -rp "ALL DATA on $DISK will be erased. Type 'yes' to continue: " ok
[[ "$ok" == "yes" ]] || die "aborted"

read -rsp "Password for $USERNAME (also used for root): " PASSWORD; echo
[[ -n "$PASSWORD" ]] || die "empty password"

timedatectl set-ntp true

# Partition: 512M EFI + rest root (ext4)
sgdisk --zap-all "$DISK"
sgdisk -n1:0:+512M -t1:ef00 -c1:EFI "$DISK"
sgdisk -n2:0:0 -t2:8300 -c2:root "$DISK"
partprobe "$DISK"
sleep 2
if [[ "$DISK" =~ [0-9]$ ]]; then P="${DISK}p"; else P="$DISK"; fi
EFI="${P}1"; ROOT="${P}2"

mkfs.fat -F32 "$EFI"
mkfs.ext4 -F "$ROOT"
mount "$ROOT" /mnt
mount --mkdir "$EFI" /mnt/boot

pacstrap -K /mnt base linux linux-firmware sudo networkmanager grub efibootmgr \
    gnome gnome-tweaks gdm xdg-desktop-portal-gnome pipewire wireplumber \
    pipewire-pulse xorg-xwayland qt5-wayland qt6-wayland $(
        lscpu | grep -qi intel && echo intel-ucode
        lscpu | grep -qi amd && echo amd-ucode
    )

genfstab -U /mnt >> /mnt/etc/fstab

arch-chroot /mnt /bin/bash -euo pipefail <<CHROOT
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc
sed -i "s/^#$LOCALE/$LOCALE/" /etc/locale.gen
locale-gen
echo "LANG=$LOCALE" > /etc/locale.conf
echo "KEYMAP=$KEYMAP" > /etc/vconsole.conf
echo "$HOSTNAME" > /etc/hostname

useradd -m -G wheel -s /bin/bash "$USERNAME"
echo "$USERNAME:$PASSWORD" | chpasswd
echo "root:$PASSWORD" | chpasswd
echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/10-wheel
chmod 440 /etc/sudoers.d/10-wheel

grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

# GDM uses Wayland by default; make sure it is not disabled
rm -f /etc/udev/rules.d/61-gdm.rules
systemctl enable gdm NetworkManager
CHROOT

umount -R /mnt
echo "Installation complete. Reboot and log in via GDM (GNOME on Wayland)."
