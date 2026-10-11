# arch-linux-build
Arch Linux install script: GNOME on Wayland (GDM), LUKS2 encryption, Secure Boot, and optional TPM2 unlock.

Before installing, boot the Arch live ISO in UEFI mode and put the firmware in Secure Boot Setup Mode by clearing its Secure Boot keys. The installer enrolls its own keys and signs systemd-boot and the kernel. After installation, enable Secure Boot in firmware before booting the new system. The installer cannot change firmware settings.

It prompts for hostname, username, timezone (default Pacific/Auckland), locale (default en_NZ.UTF-8), keymap (default us), user password, LUKS passphrase, target disk, and
whether to split the disk into separate encrypted root and /home partitions.
The user is a normal (non-root) account in the `wheel` group and uses `sudo` for admin
tasks; the root account is locked. If a TPM2 is present, you can enroll it (PCR 7) to
unlock the disk automatically; the passphrase remains as fallback. Enroll TPM2 only
after enabling Secure Boot, so PCR 7 matches the final boot state.

The installer also enrolls Microsoft's Secure Boot certificates. Firmware key
management menus vary; do not restore factory keys after installing the custom keys.

Warning: the target disk is wiped.
