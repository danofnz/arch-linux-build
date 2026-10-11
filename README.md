# arch-linux-build
Arch Linux install script: GNOME on Wayland (GDM), LUKS2 encryption, and optional TPM2 unlock.

Boot the Arch live ISO in UEFI mode with Secure Boot disabled, since the ISO is not signed for Secure Boot. The installer does not configure Secure Boot; the installed system will boot with Secure Boot disabled.

It prompts for hostname, username, timezone (default Pacific/Auckland), locale (default en_NZ.UTF-8), keymap (default us), user password, LUKS passphrase, target disk, and
whether to split the disk into separate encrypted root and /home partitions.
The user is a normal (non-root) account in the `wheel` group and uses `sudo` for admin
tasks; the root account is locked. If a TPM2 is present, you can enroll it (PCR 7) to
unlock the disk automatically; the passphrase remains as fallback. If you enroll
TPM2, PCR 7 reflects the current Secure Boot state. Changing that state later may
require re-enrollment.

Warning: the target disk is wiped.
