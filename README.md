# arch-linux-build
Arch Linux install script for a GNOME desktop running on Wayland (GDM).

Boot the Arch live ISO in UEFI mode, get this repo, then run as root:

    DISK=/dev/sda HOSTNAME_NEW=archgnome USERNAME_NEW=me TIMEZONE=Pacific/Auckland ./install.sh

Warning: the target disk is wiped.
