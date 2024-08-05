### Introduction

[![ShellCheck](https://github.com/TommyTran732/Arch-Setup-Script/actions/workflows/shellcheck.yml/badge.svg)](https://github.com/TommyTran732/Arch-Setup-Script/actions/workflows/shellcheck.yml)

Welcome to my fork of [Arch-Setup-Script](https://github.com/tommytran732/Arch-Setup-Script), a high-quality installer for Arch Linux. It sets up a BTRFS system with encrypted `/boot` and full snapper support (both snapshotting and rollback work!). It also includes various system hardening configurations.

The original script was based on [easy-arch](https://github.com/classy-giraffe/easy-arch). However, it diverges substantially from the original project does not follow its development.

### On a personal note:
I will admit, I prefer doing things [The Arch Way](https://wiki.archlinux.org/index.php/Arch_Linux#Principles), but when your average bootstrapping of Arch Linux involves hundreds of systems a month, ease-of-use **does** become a major factor -- and having tried numerous scripts out there, fixing the least broken one, seemed like the best use of limited time.

After all, if you:

- Do something once, do it from the command line.
- Do something **more** than once, script it.

I will submit some of the changes here back to upstream as well.

If you have any questions about this script as a whole (this is literally just my working fork), please visit the _upstream_ Matrix group: https://invite.arcticfoxes.net/#/#tommy:arcticfoxes.net

### How to use it?
1. Download an Arch Linux ISO from [here](https://archlinux.org/download/)
2. Flash the ISO onto an [USB Flash Drive](https://wiki.archlinux.org/index.php/USB_flash_installation_medium).
3. Boot the live environment.
4. Connect to the internet.
5. `git clone https://github.com/funk-on-code/Arch-Setup-Script/`
6. `cd Arch-Setup-Script`
7. `chmod u+x ./install.sh`
8. `./install.sh`

### Snapper behavior
The partition layout I use allows us to replicate the behavior found in openSUSE 🦎
1. Snapper rollback <number> works! You will no longer need to manually rollback from a live USB like you would with the @ and @home layout suggested in the Arch Wiki.
2. You can boot into a readonly snapshot! GDM and other services will start normally so you can get in and verify that everything works before rolling back.
3. Automatic snapshots on pacman install/update/remove operations
4. Directories such as `/boot`, `/boot/efi`, `/var/log`, `/var/crash`, `/var/tmp`, `/var/spool`, /`var/lib/libvirt/images` are excluded from the snapshots as they either should be persistent or are just temporary files. `/cryptkey` is excluded as we do not want the encryption key to be included in the snapshots, which could be sent to another device as a backup.
5. GRUB will boot into the default BTRFS snapshot set by snapper. Like on openSUSE, your running system will always be a read-write snapshot in `@/.snapshots/X/snapshot`. 

### Security considerations

Since this is an encrypted `/boot` setup, GRUB will prompt you for your encryption password and decrypt the drive so that it can access the kernel and initramfs. I am unaware of any way to make it use a TPM + PIN setup.

The implication of this is that an attacker can change your secure boot state with a programmer, replace your grubx64.efi and it will not be detected until its too late.

This type of attack can theoratically be solved by splitting /boot out to a seperate partition and encrypt the root filesystem separately. The key protector for the root filesystem can then be sealed to a TPM with PCR 0+1+2+3+5+7+14. It is a bit more complicated to set up so my installer does not support this (yet!).
