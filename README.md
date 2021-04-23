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
1. Enabled AppArmor
2. SUSE - like partition layout
3. Default umask to 077
4. Firewalld is enabled by default
5. Improved kernel settings for better security
6. Minimally setup GNOME 40

### Partitions layout 

| Partition Number | Label     | Size              | Mountpoint | Filesystem             |
|------------------|-----------|-------------------|------------|------------------------|
| 1                | ESP       | 300 MiB           | /boot/efi  | FAT32                  |
| 2                | cryptroot | Rest of the disk  | /          | Encrypted BTRFS (LUKS1)|

The **partitions layout** is pretty straightforward, it's inspired by [this section](https://wiki.archlinux.org/index.php/Dm-crypt/Encrypting_an_entire_system#Btrfs_subvolumes_with_swap) of the Arch Wiki. As you can see there's just a couple of partitions:
1. A **FAT32**, 512MiB sized, mounted at `/boot/efi` for the ESP.
2. A **LUKS encrypted container**, which takes the rest of the disk space, mounted at `/` for the rootfs.
3. /boot is **encrypted**.
