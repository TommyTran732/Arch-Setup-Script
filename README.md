### Introduction
Welcome to my fork of [Arch-Setup-Script](https://github.com/tommytran732/Arch-Setup-Script), a **script** made in order to boostrap a basic **Arch Linux** environment with **snapshots** and **encryption** by using a fully automated process (UEFI only).


### On a personal note:
I will admit, I prefer doing things [The Arch Way](https://wiki.archlinux.org/index.php/Arch_Linux#Principles), but when your average bootstrapping of Arch Linux involves hundreds of systems a month, ease-of-use **does** become a major factor -- and having tried numerous scripts out there, fixing the least broken one, seemed like the best use of limited time.

After all, if you:

- Do something once, do it from the command line.
- Do something **more** than once, script it.

I will submit some of the changes here back to upstream as well.

If you have any questions about this script as a whole (this is literally just my working fork), please visit the upstream projects Matrix group: https://matrix.to/#/#tommytran732:matrix.org

### How does it work?
1. Download an Arch Linux ISO from [here](https://archlinux.org/download/)
2. Flash the ISO onto an [USB Flash Drive](https://wiki.archlinux.org/index.php/USB_flash_installation_medium).
3. Boot the live environment.
4. Connect to the internet.
5. `pacman -S git -y`
5. `git clone https://github.com/syonekura/Arch-Setup-Script/`
6. `cd Arch-Setup-Script`
7. `./desktop.sh`

### Secure Boot
The Secure Boot script can be run after you have rebooted into the system to automate the process of generating your own keys and setting up Secure Boot described at https://wiki.archlinux.org/title/Unified_Extensible_Firmware_Interface/Secure_Boot. Please make sure that your firmware is in Setup mode and the TPM is disabled.

Currently, there is an problem where GRUB requires tpm.mod to be included for signature verification, but if tpm.mod is included and the TPM is enabled it will also attempt to do Measured Boot, breaking the Arch Linux snapshots menu created by grub-btrfs. I have yet to find a solution for this issue.

### Changes to the original project
1. Fixes the ESP sizing for encrypted boot.
2. Fixes the wiping disk to support spinning disk and nvme's alike.
3. Adds a user account suitable for both Desktop and Server use alike.
4. Installs a "full-stack(tm)" GNOME Desktop.

### Snapper behavior
The partition layout I use rallows us to replicate the behavior found in openSUSE 🦎
1. Snapper rollback <number> works! You will no longer need to manually rollback from a live USB like you would with the @ and @home layout suggested in the Arch Wiki.
2. You can boot into a readonly snapshot! GDM and other services will start normally so you can get in and verify that everything works before rolling back.
3. Automatic snapshots on pacman install/update/remove operations
4. Directories such as /boot, /boot/efi, /var/log, /var/crash, /var/tmp, /var/spool, /var/lib/libvirt/images are excluded from the snapshots as they either should be persistent or are just temporary files. /cryptkey is excluded as we do not want the encryption key to be included in the snapshots, which could be sent to another device as a backup.
5. GRUB will boot into the default BTRFS snapshot set by snapper. Like on SUSE, your running system will always be a read-write snapshot in @/.snapshots/X/snapshot. 

### Partitions layout 

| Partition/Subvolume | Label                        | Mountpoint               | Notes                       |
|---------------------|------------------------------|--------------------------|-----------------------------|
| 1                   | ESP                          | /boot/efi                | Unencrypted FAT32           |
| 2                   | @/.snapshots/X/snapshot      | /                        | Encrypted BTRFS             |
| 3                   | @/boot                       | /boot/                   | Encrypted BTRFS (nodatacow) |
| 4                   | @/root                       | /root                    | Encrypted BTRFS             |
| 5                   | @/home                       | /home                    | Encrypted BTRFS             |
| 6                   | @/.snapshots                 | /.snapshots              | Encrypted BTRFS             |
| 7                   | @/srv                        | /srv                     | Encrypted BTRFS (nodatacow) |
| 8                   | @/var_log                    | /var/log                 | Encrypted BTRFS (nodatacow) |
| 9                   | @/var_log/journal            | /var/log/journal         | Encrypted BTRFS (nodatacow) |
| 10                  | @/var_crash                  | /var/crash               | Encrypted BTRFS (nodatacow) |
| 11                  | @/var_cache                  | /var/cache               | Encrypted BTRFS (nodatacow) |
| 12                  | @/var_tmp                    | /var/tmp                 | Encrypted BTRFS (nodatacow) |
| 13                  | @/var_spool                  | /var/spool               | Encrypted BTRFS (nodatacow) |
| 14                  | @/var_lib_libvirt_images     | /var/lib/libvirt/images  | Encrypted BTRFS (nodatacow) |
| 15                  | @/var_lib_machines           | /var/lib/machines        | Encrypted BTRFS (nodatacow) |
| 16                  | @/var_lib_gdm                | /var/lib/gdm             | Encrypted BTRFS (nodatacow) |
| 17                  | @/var_lib_AccountsService    | /var/lib/AccountsService | Encrypted BTRFS (nodatacow) |
| 18                  | @/cryptkey                   | /cryptkey                | Encrypted BTRFS (nodatacow) |

### LUKS1 and Encrypted /boot (Mumbo Jumbo stuff)
This is the same setup that is used on openSUSE. One problem with the way Secure Boot currently works is that the initramfs and a variety of things in /boot are not validated by GRUB whatsoever, even if Secure Boot is active. Thus, they are vulnerable to tampering. My approach as of now is to encrypt the entire /boot partition and have the only that is unencrypted - the grubx64.efi stub - validated by the firmware. 

Ideally, I could use GRUB's GPG verification for the initramfs and its configuration files and what not, but then I need to create hooks to sign them everytime they get updated (when a new initramfs gets generated, when grub-btrfs.path gets triggered, when grub gets updated and its config files change, etc). It is quite a tedious task and I have yet to implement or test this out.

As for why LUKS1 is used, GRUB 2.06 does not work nicely with LUKS2 yet. grub-install will not make GRUB auto detect the LUKS2 partition, and GRUB itself does not support Argon2id (cryptsetup default) as of now anyways. It makes little sense to use GRUB with LUKS2 in its current state, thus I am using LUKS1 to avoid the headache.

You may also see an a keyfile being created by the script and stored at /cryptkey. This is to avoid getting 2 encryption password prompts (one for GRUB to decrypt the disk so that it can get to the kernel, the initramfs and configuration files and one for the kernel itself to start up the rest of the boot process). As the key resides on an encrypted partition (and so does the initramfs that stores a copy of it), security risks should be minimal. The only time an attacker would have access to it is when they have root, at which point you have a much, much more serious problem. The procedure I am using is describe at https://en.opensuse.org/SDB:Encrypted_root_file_system.
