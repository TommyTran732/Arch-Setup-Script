#!/usr/bin/env -S bash -e

# Cleaning the TTY.
clear

# Selecting the kernel flavor to install. 
kernel_selector () {
    echo "List of kernels:"
    echo "1) Stable — Vanilla Linux kernel and modules, with a few patches applied."
    echo "2) Hardened — A security-focused Linux kernel."
    echo "3) Longterm — Long-term support (LTS) Linux kernel and modules."
    echo "4) Zen Kernel — Optimized for desktop usage."
    read -r -p "Insert the number of the corresponding kernel: " choice
    echo "$choice will be installed"
    case $choice in
        1 ) kernel=linux
            ;;
        2 ) kernel=linux-hardened
            ;;
        3 ) kernel=linux-lts
            ;;
        4 ) kernel=linux-zen
            ;;
        * ) echo "You did not enter a valid selection."
            kernel_selector
    esac
}

# Checking the microcode to install.
CPU=$(grep vendor_id /proc/cpuinfo)
if [[ $CPU == *"AuthenticAMD"* ]]
then
    microcode=amd-ucode
else
    microcode=intel-ucode
fi

# Selecting the target for the installation.
PS3="Select the disk where Arch Linux is going to be installed: "
select ENTRY in $(lsblk -dpnoNAME|grep -P "/dev/sd|nvme");
do
    DISK=$ENTRY
    echo "Installing Arch Linux on $DISK."
    break
done

# Deleting old partition scheme.
read -r -p "This will delete the current partition table on $DISK. Do you agree [y/N]? " response
response=${response,,}
if [[ "$response" =~ ^(yes|y)$ ]]
then
    wipefs -af $DISK &>/dev/null
    sgdisk -Zo $DISK &>/dev/null
else
    echo "Quitting."
    exit
fi

# Creating a new partition scheme.
echo "Creating new partition scheme on $DISK."
parted -s "$DISK" \
    mklabel gpt \
    mkpart ESP fat32 1MiB 101MiB \
    mkpart cryptroot 101MiB 100% \

ESP="/dev/disk/by-partlabel/ESP"
cryptroot="/dev/disk/by-partlabel/cryptroot"

# Informing the Kernel of the changes.
echo "Informing the Kernel about the disk changes."
partprobe $DISK

# Formatting the ESP as FAT32.
echo "Formatting the EFI Partition as FAT32."
mkfs.fat -F 32 $ESP &>/dev/null

# Creating a LUKS Container for the root partition.
echo "Creating LUKS Container for the root partition."
cryptsetup --type luks1 luksFormat $cryptroot
echo "Opening the newly created LUKS Container."
cryptsetup open $cryptroot cryptroot
BTRFS="/dev/mapper/cryptroot"

# Formatting the LUKS Container as BTRFS.
echo "Formatting the LUKS container as BTRFS."
mkfs.btrfs $BTRFS &>/dev/null
mount $BTRFS /mnt

# Creating BTRFS subvolumes.
echo "Creating BTRFS subvolumes."
btrfs subvolume create /mnt/@ &>/dev/null
btrfs subvolume create /mnt/@/.snapshots &>/dev/null
mkdir -p /mnt/@/.snapshots/1 &>/dev/null
btrfs subvolume create /mnt/@/.snapshots/1/snapshot &>/dev/null
mkdir -p /mnt/@/boot
btrfs subvolume create /mnt/@/boot/grub/ &>/dev/null
btrfs subvolume create /mnt/@/home &>/dev/null
btrfs subvolume create /mnt/@/root &>/dev/null
btrfs subvolume create /mnt/@/srv &>/dev/null
btrfs subvolume create /mnt/@/tmp &>/dev/null
btrfs subvolume create /mnt/@/var_log &>/dev/null
btrfs subvolume create /mnt/@/var_crash &>/dev/null
btrfs subvolume create /mnt/@/var_cache &>/dev/null
btrfs subvolume create /mnt/@/var_tmp &>/dev/null
btrfs subvolume create /mnt/@/var_spool &>/dev/null
btrfs subvolume create /mnt/@/var_lib_gdm &>/dev/null
btrfs subvolume create /mnt/@/var_lib_AccountsService &>/dev/null
btrfs subvolume create /mnt/@/var_lib_libvirt_images &>/dev/null
chattr +C /mnt/@/boot/grub
chattr +C /mnt/@/srv
chattr +C /mnt/@/tmp
chattr +C /mnt/@/var_log
chattr +C /mnt/@/var_crash
chattr +C /mnt/@/var_cache
chattr +C /mnt/@/var_tmp
chattr +C /mnt/@/var_spool
chattr +C /mnt/@/var_lib_libvirt_images
btrfs subvolume set-default $(btrfs subvolume list /mnt | grep "@/.snapshots/1/snapshot" | grep -oP '(?<=ID )[0-9]+') /mnt

cat << EOF >> /mnt/@/.snapshots/1/info.xml
<?xml version="1.0"?>
<snapshot>
   <type>single</type>
   <num>1</num>
   <description>First Root Filesystem</description>
</snapshot>
EOF

chmod 600 /mnt/@/.snapshots/1/info.xml

# Mounting the newly created subvolumes.
umount /mnt
echo "Mounting the newly created subvolumes."
mount -o ssd,noatime,space_cache,compress=zstd:15 $BTRFS /mnt
mkdir -p /mnt/{/boot/grub,root,home,.snapshots,srv,tmp,/var/log,/var/crash,/var/cache,/var/tmp,/var/spool,/var/lib/gdm,/var/lib/AccountsService,/var/lib/libvirt/images}
mount -o ssd,noatime,space_cache,compress=zstd:15,nodatacow,subvol=@/boot/grub $BTRFS /mnt/boot/grub
mount -o ssd,noatime,space_cache,compress=zstd:15,subvol=@/root $BTRFS /mnt/root 
mount -o ssd,noatime,space_cache.compress=zstd:15,subvol=@/home $BTRFS /mnt/home
mount -o ssd,noatime,space_cache,compress=zstd:15,subvol=@/.snapshots $BTRFS /mnt/.snapshots
mount -o ssd,noatime,space_cache.compress=zstd:15,subvol=@/srv $BTRFS /mnt/srv
mount -o ssd,noatime,space_cache.compress=zstd:15,subvol=@/srv $BTRFS /mnt/tmp
mount -o ssd,noatime,space_cache,compress=zstd:15,nodatacow,subvol=@/var_log $BTRFS /mnt/var/log
mount -o ssd,noatime,space_cache,compress=zstd:15,nodatacow,subvol=@/var_crash $BTRFS /mnt/var/crash
mount -o ssd,noatime,space_cache,compress=zstd:15,nodatacow,subvol=@/var_cache $BTRFS /mnt/var/cache
mount -o ssd,noatime,space_cache,compress=zstd:15,nodatacow,subvol=@/var_tmp $BTRFS /mnt/var/tmp
mount -o ssd,noatime,space_cache,compress=zstd:15,nodatacow,subvol=@/var_tmp $BTRFS /mnt/var/spool
mount -o ssd,noatime,space_cache,compress=zstd:15,subvol=@/var_lib_gdm $BTRFS /mnt/var/lib/gdm
mount -o ssd,noatime,space_cache,compress=zstd:15,subvol=@/var_lib_AccountsService $BTRFS /mnt/var/lib/AccountsService
mount -o ssd,noatime,space_cache,compress=zstd:15,subvol=@/var_lib_libvirt_images $BTRFS /mnt/var/lib/libvirt/images
mkdir -p /mnt/boot/efi
mount $ESP /mnt/boot/efi



kernel_selector

# Pacstrap (setting up a base sytem onto the new root).
echo "Installing the base system (it may take a while)."
pacstrap /mnt base base-devel ${kernel} ${microcode} linux-firmware grub grub-btrfs snapper efibootmgr sudo networkmanager apparmor pipewire nano gnome-shell gdm gnome-control-center gnome-terminal gnome-software gnome-tweaks nautilus flatpak xdg-user-dirs firewalld 

# Generating /etc/fstab.
echo "Generating a new fstab."
genfstab -U /mnt >> /mnt/etc/fstab
sed -i 's#subvolid=258,subvol=/@/.snapshots/1/snapshot,subvol=@/.snapshots/1/snapshot,##g' /mnt/etc/fstab

# Setting hostname.
read -r -p "Please enter the hostname: " hostname
echo $hostname > /mnt/etc/hostname

# Setting up locales.
read -r -p "Please insert the locale you use in this format (xx_XX): " locale
echo "$locale.UTF-8 UTF-8"  > /mnt/etc/locale.gen
echo "LANG=$locale.UTF-8" > /mnt/etc/locale.conf

# Setting up keyboard layout.
read -r -p "Please insert the keyboard layout you use: " kblayout
echo "KEYMAP=$kblayout" > /mnt/etc/vconsole.conf

# Setting hosts file.
echo "Setting hosts file."
cat > /mnt/etc/hosts <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   $hostname.localdomain   $hostname
EOF

# Configuring /etc/mkinitcpio.conf
echo "Configuring /etc/mkinitcpio for ZSTD compression and LUKS hook."
sed -i -e 's,#COMPRESSION="zstd",COMPRESSION="zstd",g' /mnt/etc/mkinitcpio.conf
sed -i -e 's,modconf block filesystems keyboard,keyboard keymap modconf block encrypt filesystems,g' /mnt/etc/mkinitcpio.conf

# Enabling LUKS in GRUB and setting the UUID of the LUKS container.
UUID=$(blkid $cryptroot | cut -f2 -d'"')
sed -i 's/#\(GRUB_ENABLE_CRYPTODISK=y\)/\1/' /mnt/etc/default/grub
sed -i -e "s,quiet,quiet cryptdevice=UUID=$UUID:cryptroot root=$BTRFS,g" /mnt/etc/default/grub
sed -i -e "s#root=/dev/mapper/cryptroot#root=/dev/mapper/cryptroot lsm=lockdown,yama,apparmor,bpf#g" /mnt/etc/default/grub
echo "" >> /mnt/etc/default/grub
echo -e "# Booting with BTRFS subvolume\nGRUB_BTRFS_OVERRIDE_BOOT_PARTITION_DETECTION=true" >> /mnt/etc/default/grub

# Adding keyfile to the initramfs to avoid double password.
dd bs=512 count=4 if=/dev/random of=/mnt/.root.key iflag=fullblock &>/dev/null
chmod 000 /mnt/.root.key &>/dev/null
cryptsetup -v luksAddKey /dev/disk/by-partlabel/cryptroot /mnt/.root.key
#I also remove the quiet flag here, since not having any sort of output is a pain
sed -i -e "s,quiet,cryptdevice=UUID=$UUID:cryptroot root=$BTRFS cryptkey=rootfs:/.root.key,g" /mnt/etc/default/grub
sed -i 's#FILES=()#FILES=(/.root.key)#g' /mnt/etc/mkinitcpio.conf

# Security kernel settings.
echo "kernel.kptr_restrict = 2" > /mnt/etc/sysctl.d/51-kptr-restrict.conf
echo "kernel.kexec_load_disabled = 1" > /mnt/etc/sysctl.d/51-kexec-restrict.conf
cat << EOF >> /mnt/etc/sysctl.d/10-security.conf
    fs.protected_hardlinks = 1
    fs.protected_symlinks = 1
    net.core.bpf_jit_harden = 2
    kernel.yama.ptrace_scope = 3
EOF

# Configuring the system.    
arch-chroot /mnt /bin/bash -e <<EOF
    
    # Setting up timezone.
    ln -sf /usr/share/zoneinfo/$(curl -s http://ip-api.com/line?fields=timezone) /etc/localtime &>/dev/null
    
    # Setting up clock.
    hwclock --systohc
    
    # Generating locales.
    echo "Generating locales."
    locale-gen &>/dev/null
    
    # Generating a new initramfs.
    echo "Creating a new initramfs."
    chmod 600 /boot/initramfs-linux* &>/dev/null
    mkinitcpio -P &>/dev/null

    # Snapper configuration
    umount /.snapshots
    rm -r /.snapshots
    snapper --no-dbus -c root create-config /
    btrfs subvolume delete /.snapshots
    mkdir /.snapshots
    mount -a
    chmod 750 /.snapshots
    systemctl enable grub-btrfs.path

    # Installing GRUB.
    echo "Installing GRUB on /boot."
    grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB &>/dev/null
    sed -i 's#"rootflags=subvol=${rootsubvol}"##g' /etc/grub.d/10_linux
    sed -i 's#"rootflags=subvol=${rootsubvol}"##g' /etc/grub.d/20_linux_xen
    pacman -S --noconfirm snap-pac
    
    # Creating grub config file.
    echo "Creating GRUB config file."
    grub-mkconfig -o /boot/grub/grub.cfg &>/dev/null
EOF

# Setting root password.
echo "Setting root password."
arch-chroot /mnt /bin/passwd

# Enabling auto-trimming service.
echo "Enabling auto-trimming."
systemctl enable fstrim.timer --root=/mnt &>/dev/null

# Enabling NetworkManager service.
echo "Enabling NetworkManager."
systemctl enable NetworkManager --root=/mnt &>/dev/null

# Enabling GDM
systemctl enable gdm --root=/mnt &>/dev/null

# Enabling AppArmor
systemctl enable apparmor --root=/mnt &>/dev/null

# Enabling Firewalld
systemctl enable firewalld --root=/mnt &>/dev/null

# Setting umask to 077
sed -i 's/022/077/g' /mnt/etc/profile
echo "" >> /mnt/etc/bash.bashrc
echo "umask 077" >> /mnt/etc/bash.bashrc

#Blacklist Firewire SBP2
echo "blacklist firewire-sbp2" | sudo tee /mnt/etc/modprobe.d/blacklist.conf

echo "Done, you may now wish to reboot (further changes can be done by chrooting into /mnt)."
exit
