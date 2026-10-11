# arch-linux-build
Arch Linux install script: GNOME on Wayland (GDM), LUKS2 encryption, optional TPM2 unlock.

Boot the Arch live ISO in UEFI mode, get this repo, then run as root: `./install.sh`

It prompts for hostname, username, user password, LUKS passphrase, target disk, and
whether to split the disk into separate encrypted root and /home partitions.
The user is a normal (non-root) account in the `wheel` group and uses `sudo` for admin
tasks; the root account is locked. If a TPM2 is present, you can enroll it (PCR 7) to
unlock the disk automatically; the passphrase remains as fallback.

Warning: the target disk is wiped.
