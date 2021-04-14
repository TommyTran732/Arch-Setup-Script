### Introduction
This is my fork of [easy-arch](https://github.com/classy-giraffe/easy-arch), a **script** made in order to boostrap a basic **Arch Linux** environment with **snapshots** and **encryption** by using a fully automated process.

### How does it work?
1. Download an Arch Linux ISO from [here](https://archlinux.org/download/)
2. Flash the ISO onto an [USB Flash Drive](https://wiki.archlinux.org/index.php/USB_flash_installation_medium).
3. Boot the live environment.
4. Connect to the internet.
5. `git clone https://github.com/tommytran732/Arch-Setup-Script/edit/main/README.md`
6. `cd Arch-Setup-Script`
7. `chmod u+x ./install.sh && ./install.sh`

### Changes to the original project
1. /boot is now encrypted
2. Added option to select your own kernel flavor
3. Enabled AppArmor
4. Removed swap partition (I will add zram auto config later)
5. Replaced Snapper with Timeshift (snapper rollback only works nicely with openSUSE's layout and openSUSE's GRUB. Since the current layout works better with Timeshift and we don't have any GRUB package with SUSE's patches on the AUR, I opt in for Timeshift instead.
6. The entire /var, not /var/log is in its own subvolume. There are more things that should not be included and restore with the main system, such as docker containers and virtual machines.
7. No @snapshot subvolume, since we are setting this up to use with Timeshift.
8. Added microcode installation

### Partitions layout 

| Partition Number | Label     | Size              | Mountpoint | Filesystem             |
|------------------|-----------|-------------------|------------|------------------------|
| 1                | ESP       | 512 MiB           | /boot/efi  | FAT32                  |
| 2                | Cryptroot | Rest of the disk  | /          | Encrypted BTRFS (LUKS1)|

The **partitions layout** is pretty straightforward, it's inspired by [this section](https://wiki.archlinux.org/index.php/Dm-crypt/Encrypting_an_entire_system#Btrfs_subvolumes_with_swap) of the Arch Wiki. As you can see there's just a couple of partitions:
1. A **FAT32**, 512MiB sized, mounted at `/boot` for the ESP.
2. A **LUKS encrypted container**, which takes the rest of the disk space, mounted at `/` for the rootfs.
3. /boot is **encrypted**.

### BTRFS subvolumes layout

| Subvolume Number | Subvolume Name | Mountpoint       |
|------------------|----------------|------------------|
| 1                | @              | /                |
| 2                | @boot          | /boot
| 3                | @home          | /home            |
| 4                | @var           | /var             |

The **BTRFS subvolumes layout** follows the traditional and suggested layout used by **Snapper**, you can find it [here](https://wiki.archlinux.org/index.php/Snapper#Suggested_filesystem_layout). I only added a swap subvolume in case you need a swapfile, but it's totally optional. You'll be asked if you want it or not during the script execution. Here's a brief explanation of the **BTRFS layout** I chose:
1. `@` mounted as `/`.
2. `@boot` mounted as `/boot`.
3. `@home` mounted as `/home`.
4. `@var` mounted as `/var`.
