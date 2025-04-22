#!/bin/bash

# Copyright (C) 2021-2024 Thien Tran, Tommaso Chiti
#
# Licensed under the Apache License, Version 2.0 (the "License"); you may not
# use this file except in compliance with the License. You may obtain a copy of
# the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the specific language governing permissions and limitations under
# the License.

set -eu

output(){
    printf '\e[1;34m%-6s\e[m\n' "${@}"
}

unpriv(){
    sudo -u nobody "$@"
}

installation_date=$(date "+%Y-%m-%d %H:%M:%S")

# Check if this is a VM
virtualization=$(systemd-detect-virt)

install_mode_selector() {
    output 'Is this a desktop or server installation?'
    output '1) Desktop'
    output '2) Server'
    output 'Insert the number of your selection:'
    read -r choice
    case $choice in
        1 ) install_mode=desktop
            ;;
        2 ) install_mode=server
            ;;
        * ) output 'You did not enter a valid selection.'
            install_mode_selector
    esac
}

luks_prompt(){
    if [ "${virtualization}" != 'none' ]; then
        output "Virtual machine detected. Do you want to set up LUKS?"
        output '1) No'
        output '2) Yes'
        output 'Insert the number of your selection:'
        read -r choice
        case $choice in
            1 ) use_luks='0'
                ;;
            2 ) use_luks='1'
                ;;
            * ) output 'You did not enter a valid selection.'
                luks_prompt
        esac
    else
        use_luks='1'
    fi
}

luks_passphrase_prompt () {
    if [ "${use_luks}" = '1' ]; then
        output 'Enter your encryption passphrase (the passphrase will not be shown on the screen):'
        read -r -s luks_passphrase

        if [ -z "${luks_passphrase}" ]; then
            output 'To use encryption, you need to enter a passphrase.'
            luks_passphrase_prompt
        fi

        output 'Confirm your encryption passphrase (the passphrase will not be shown on the screen):'
        read -r -s luks_passphrase2
        if [ "${luks_passphrase}" != "${luks_passphrase2}" ]; then
            output 'Passphrases do not match, please try again.'
            luks_passphrase_prompt
        fi
    fi
}

disk_prompt (){
    lsblk
    output 'Please select the number of the corresponding disk (e.g. 1):'
    select entry in $(lsblk -dpnoNAME|grep -P "/dev/nvme|sd|mmcblk|vd");
    do
        disk="${entry}"
        output "Arch Linux will be installed on the following disk: ${disk}"
        break
    done
}

username_prompt (){
    output 'Please enter the name for a user account:'
    read -r username

    if [ -z "${username}" ]; then
        output 'Sorry, You need to enter a username.'
        username_prompt
    fi
}

fullname_prompt (){
    output 'Please enter the full name for the user account:'
    read -r fullname

    if [ -z "${fullname}" ]; then
        output 'Please enter the full name of the users account.'
        fullname_prompt
    fi
}

user_password_prompt () {
    output 'Enter your user password (the password will not be shown on the screen):'
    read -r -s user_password

    if [ -z "${user_password}" ]; then
        output 'You need to enter a password.'
        user_password_prompt
    fi

    output 'Confirm your user password (the password will not be shown on the screen):'
    read -r -s user_password2
    if [ "${user_password}" != "${user_password2}" ]; then
        output 'Passwords do not match, please try again.'
        user_password_prompt
    fi
}

hostname_prompt (){
    if [ "${install_mode}" = 'server' ]; then
        output 'Enter your hostname:'
        read -r hostname

        if [ -z "${hostname}" ]; then
            output 'You need to enter a hostname.'
            hostname_prompt
        fi
    else
        hostname='localhost'
    fi
}

network_daemon_prompt(){
    if [ "${install_mode}" = 'server' ]; then
        output 'Which network daemon do you want to use'
        output '1) networkmanager'
        output '2) systemd-networkd'
        output 'Insert the number of your selection:'
        read -r choice
        case $choice in
            1 ) network_daemon='networkmanager'
                ;;
            2 ) network_daemon='systemd-networkd'
                ;;
            * ) output 'You did not enter a valid selection.'
            install_mode_selector
        esac
    else
        network_daemon='networkmanager'
    fi
}

# Set hardcoded variables (temporary, these will be replaced by future prompts)
locale=en_US
kblayout=us

# Cleaning the TTY
clear

# Initial prompts
install_mode_selector 
luks_prompt
luks_passphrase_prompt
disk_prompt
username_prompt
fullname_prompt
user_password_prompt
hostname_prompt
network_daemon_prompt

# Installation

## Updating the live environment usually causes more problems than its worth, and quite often can't be done without remounting cowspace with more capacity
pacman -Sy

## Installing curl
pacman -S --noconfirm curl

## Wipe the disk
sgdisk --zap-all "${disk}"

## Creating a new partition scheme
output "Creating new partition scheme on ${disk}."
sgdisk -g "${disk}"
sgdisk -I -n 1:0:+512M -t 1:ef00 -c 1:'ESP' "${disk}"
sgdisk -I -n 2:0:0 -c 2:'rootfs' "${disk}"

ESP='/dev/disk/by-partlabel/ESP'

if [ "${use_luks}" = '1' ]; then
    cryptroot='/dev/disk/by-partlabel/rootfs'
fi

## Informing the Kernel of the changes
output 'Informing the Kernel about the disk changes.'
partprobe "${disk}"

## Formatting the ESP as FAT32
output 'Formatting the EFI Partition as FAT32.'
mkfs.fat -F 32 -s 2 "${ESP}"

## Creating a LUKS Container for the root partition
if [ "${use_luks}" = '1' ]; then
    output 'Creating LUKS Container for the root partition.'
    echo -n "${luks_passphrase}" | cryptsetup luksFormat --pbkdf pbkdf2 "${cryptroot}" -d -
    echo -n "${luks_passphrase}" | cryptsetup open "${cryptroot}" cryptroot -d -
    BTRFS='/dev/mapper/cryptroot'
else
    BTRFS='/dev/disk/by-partlabel/rootfs'
fi

## Formatting the partition as BTRFS
output 'Formatting the rootfs as BTRFS.'
mkfs.btrfs -f "${BTRFS}"
mount "${BTRFS}" /mnt

## Creating BTRFS subvolumes
output 'Creating BTRFS subvolumes.'

btrfs su cr /mnt/@
btrfs su cr /mnt/@/.snapshots
mkdir -p /mnt/@/.snapshots/1
btrfs su cr /mnt/@/.snapshots/1/snapshot
btrfs su cr /mnt/@/boot/
btrfs su cr /mnt/@/home
btrfs su cr /mnt/@/root
btrfs su cr /mnt/@/srv
btrfs su cr /mnt/@/var_log
btrfs su cr /mnt/@/var_crash
btrfs su cr /mnt/@/var_cache
btrfs su cr /mnt/@/var_tmp
btrfs su cr /mnt/@/var_spool
btrfs su cr /mnt/@/var_lib_libvirt_images
btrfs su cr /mnt/@/var_lib_machines
if [ "${install_mode}" = 'desktop' ]; then
    btrfs su cr /mnt/@/var_lib_gdm
    btrfs su cr /mnt/@/var_lib_AccountsService
fi

if [ "${use_luks}" = '1' ]; then
    btrfs su cr /mnt/@/cryptkey
fi

## Disable CoW on subvols we are not taking snapshots of
chattr +C /mnt/@/boot
chattr +C /mnt/@/home
chattr +C /mnt/@/root
chattr +C /mnt/@/srv
chattr +C /mnt/@/var_log
chattr +C /mnt/@/var_crash
chattr +C /mnt/@/var_cache
chattr +C /mnt/@/var_tmp
chattr +C /mnt/@/var_spool
chattr +C /mnt/@/var_lib_libvirt_images
chattr +C /mnt/@/var_lib_machines
if [ "${install_mode}" = 'desktop' ]; then
    chattr +C /mnt/@/var_lib_gdm
    chattr +C /mnt/@/var_lib_AccountsService
fi

if [ "${use_luks}" = '1' ]; then
    chattr +C /mnt/@/cryptkey
fi

## Set the default BTRFS Subvol to Snapshot 1 before pacstrapping
btrfs subvolume set-default "$(btrfs subvolume list /mnt | grep "@/.snapshots/1/snapshot" | grep -oP '(?<=ID )[0-9]+')" /mnt

echo "<?xml version=\"1.0\"?>
<snapshot>
  <type>single</type>
  <num>1</num>
  <date>${installation_date}</date>
  <description>First Root Filesystem</description>
  <cleanup>number</cleanup>
</snapshot>" > /mnt/@/.snapshots/1/info.xml

chmod 600 /mnt/@/.snapshots/1/info.xml

## Mounting the newly created subvolumes
umount /mnt
output 'Mounting the newly created subvolumes.'
mount -o ssd,noatime,compress=zstd "${BTRFS}" /mnt
mkdir -p /mnt/{boot,root,home,.snapshots,srv,tmp,var/log,var/crash,var/cache,var/tmp,var/spool,var/lib/libvirt/images,var/lib/machines}
if [ "${install_mode}" = 'desktop' ]; then
    mkdir -p /mnt/{var/lib/gdm,var/lib/AccountsService}
fi

if [ "${use_luks}" = '1' ]; then
    mkdir -p /mnt/cryptkey
fi

mount -o ssd,noatime,compress=zstd,nodev,nosuid,noexec,subvol=@/boot "${BTRFS}" /mnt/boot
mount -o ssd,noatime,compress=zstd,nodev,nosuid,subvol=@/root "${BTRFS}" /mnt/root
mount -o ssd,noatime,compress=zstd,nodev,nosuid,subvol=@/home "${BTRFS}" /mnt/home
mount -o ssd,noatime,compress=zstd,subvol=@/.snapshots "${BTRFS}" /mnt/.snapshots
mount -o ssd,noatime,compress=zstd,subvol=@/srv "${BTRFS}" /mnt/srv
mount -o ssd,noatime,compress=zstd,nodatacow,nodev,nosuid,noexec,subvol=@/var_log "${BTRFS}" /mnt/var/log
mount -o ssd,noatime,compress=zstd,nodatacow,nodev,nosuid,noexec,subvol=@/var_crash "${BTRFS}" /mnt/var/crash
mount -o ssd,noatime,compress=zstd,nodatacow,nodev,nosuid,noexec,subvol=@/var_cache "${BTRFS}" /mnt/var/cache
mount -o ssd,noatime,compress=zstd,nodatacow,nodev,nosuid,noexec,subvol=@/var_tmp "${BTRFS}" /mnt/var/tmp
mount -o ssd,noatime,compress=zstd,nodatacow,nodev,nosuid,noexec,subvol=@/var_spool "${BTRFS}" /mnt/var/spool
mount -o ssd,noatime,compress=zstd,nodatacow,nodev,nosuid,noexec,subvol=@/var_lib_libvirt_images "${BTRFS}" /mnt/var/lib/libvirt/images
mount -o ssd,noatime,compress=zstd,nodatacow,nodev,nosuid,noexec,subvol=@/var_lib_machines "${BTRFS}" /mnt/var/lib/machines

# GNOME requires /var/lib/gdm and /var/lib/AccountsService to be writeable when booting into a readonly snapshot
if [ "${install_mode}" = 'desktop' ]; then
    mount -o ssd,noatime,compress=zstd,nodatacow,nodev,nosuid,noexec,subvol=@/var_lib_gdm $BTRFS /mnt/var/lib/gdm
    mount -o ssd,noatime,compress=zstd,nodatacow,nodev,nosuid,noexec,subvol=@/var_lib_AccountsService $BTRFS /mnt/var/lib/AccountsService
fi

### The encryption is splitted as we do not want to include it in the backup with snap-pac.
if [ "${use_luks}" = '1' ]; then
    mount -o ssd,noatime,compress=zstd,nodatacow,nodev,nosuid,noexec,subvol=@/cryptkey "${BTRFS}" /mnt/cryptkey
fi

mkdir -p /mnt/boot/efi
mount -o nodev,nosuid,noexec "${ESP}" /mnt/boot/efi

## Pacstrap
output 'Installing the base system (it may take a while).'

pacstrap /mnt apparmor base chrony efibootmgr firewalld grub grub-btrfs inotify-tools linux-firmware linux-hardened linux-lts nano reflector snapper sudo zram-generator

if [ "${virtualization}" = 'none' ]; then
    CPU=$(grep vendor_id /proc/cpuinfo)
    if [[ "${CPU}" == *"AuthenticAMD"* ]]; then
        microcode=amd-ucode
    else
        microcode=intel-ucode
    fi

    pacstrap /mnt "${microcode}"
fi

if [ "${network_daemon}" = 'networkmanager' ]; then
    pacstrap /mnt networkmanager
fi

if [ "${install_mode}" = 'desktop' ]; then
    pacstrap /mnt flatpak gdm gnome-console gnome-control-center nautilus pipewire-alsa pipewire-pulse pipewire-jack
elif [ "${install_mode}" = 'server' ]; then
    pacstrap /mnt openssh unbound
fi

if [ "${virtualization}" = 'none' ]; then
    pacstrap /mnt fwupd
    echo 'UriSchemes=file;https' | sudo tee -a /mnt/etc/fwupd/fwupd.conf
elif [ "${virtualization}" = 'kvm' ]; then
    pacstrap /mnt qemu-guest-agent
    if [ "${install_mode}" = 'desktop' ]; then
        pacstrap /mnt spice-vdagent
    fi
fi

## Install snap-pac list otherwise we will have problems
pacstrap /mnt snap-pac

## Generate /etc/fstab
output 'Generating a new fstab.'
genfstab -U /mnt >> /mnt/etc/fstab
sed -i 's#,subvolid=258,subvol=/@/.snapshots/1/snapshot,subvol=@/.snapshots/1/snapshot##g' /mnt/etc/fstab

output 'Setting up hostname, locale and keyboard layout' 

## Set hostname
echo "$hostname" > /mnt/etc/hostname

## Setting hosts file
echo 'Setting hosts file.'
echo '# Loopback entries; do not change.
# For historical reasons, localhost precedes localhost.localdomain:
127.0.0.1   localhost localhost.localdomain localhost4 localhost4.localdomain4
::1         localhost localhost.localdomain localhost6 localhost6.localdomain6
# See hosts(5) for proper format and other examples:
# 192.168.1.10 foo.example.org foo
# 192.168.1.13 bar.example.org bar' > /mnt/etc/hosts

## Setup locales
echo "$locale.UTF-8 UTF-8"  > /mnt/etc/locale.gen
echo "LANG=$locale.UTF-8" > /mnt/etc/locale.conf

## Setup keyboard layout
echo "KEYMAP=$kblayout" > /mnt/etc/vconsole.conf

## Configure /etc/mkinitcpio.conf
output 'Configuring /etc/mkinitcpio for ZSTD compression and LUKS hook.'
sed -i 's/#COMPRESSION="zstd"/COMPRESSION="zstd"/g' /mnt/etc/mkinitcpio.conf
sed -i 's/^MODULES=.*/MODULES=(btrfs)/g' /mnt/etc/mkinitcpio.conf
if [ "${use_luks}" = '1' ]; then
    sed -i 's/^HOOKS=.*/HOOKS=(systemd autodetect microcode modconf keyboard sd-vconsole block sd-encrypt)/g' /mnt/etc/mkinitcpio.conf
else
    sed -i 's/^HOOKS=.*/HOOKS=(systemd autodetect microcode modconf keyboard sd-vconsole block)/g' /mnt/etc/mkinitcpio.conf
fi

## Enable LUKS in GRUB and setting the UUID of the LUKS container
if [ "${use_luks}" = '1' ]; then
    sed -i 's/#GRUB_ENABLE_CRYPTODISK=.*/GRUB_ENABLE_CRYPTODISK=y/g' /mnt/etc/default/grub
fi

## Do not preload part_msdos
sed -i 's/ part_msdos//g' /mnt/etc/default/grub

## Ensure correct GRUB settings
echo '' >> /mnt/etc/default/grub
echo '# Default to linux-hardened
GRUB_DEFAULT="1>2"

# Booting with BTRFS subvolume
GRUB_BTRFS_OVERRIDE_BOOT_PARTITION_DETECTION=true' >> /mnt/etc/default/grub

## Disable root subvol pinning
## This is **extremely** important, as snapper expects to be able to set the default btrfs subvol
# shellcheck disable=SC2016
sed -i 's/rootflags=subvol=${rootsubvol}//g' /mnt/etc/grub.d/10_linux
# shellcheck disable=SC2016
sed -i 's/rootflags=subvol=${rootsubvol}//g' /mnt/etc/grub.d/20_linux_xen

## Kernel hardening

if [ "${use_luks}" = '1' ]; then
    UUID=$(blkid -s UUID -o value "${cryptroot}")
    sed -i "s#quiet#rd.luks.name=${UUID}=cryptroot root=${BTRFS} lsm=landlock,lockdown,yama,integrity,apparmor,bpf mitigations=auto,nosmt spectre_v2=on spectre_bhi=on spec_store_bypass_disable=on tsx=off kvm.nx_huge_pages=force nosmt=force l1d_flush=on spec_rstack_overflow=safe-ret gather_data_sampling=force reg_file_data_sampling=on random.trust_bootloader=off random.trust_cpu=off intel_iommu=on amd_iommu=force_isolation efi=disable_early_pci_dma iommu=force iommu.passthrough=0 iommu.strict=1 slab_nomerge init_on_alloc=1 init_on_free=1 pti=on vsyscall=none ia32_emulation=0 page_alloc.shuffle=1 randomize_kstack_offset=on debugfs=off lockdown=confidentiality module.sig_enforce=1#g" /mnt/etc/default/grub
else
    sed -i "s#quiet#root=${BTRFS} lsm=landlock,lockdown,yama,integrity,apparmor,bpf mitigations=auto,nosmt spectre_v2=on spectre_bhi=on spec_store_bypass_disable=on tsx=off kvm.nx_huge_pages=force nosmt=force l1d_flush=on spec_rstack_overflow=safe-ret gather_data_sampling=force reg_file_data_sampling=on random.trust_bootloader=off random.trust_cpu=off intel_iommu=on amd_iommu=force_isolation efi=disable_early_pci_dma iommu=force iommu.passthrough=0 iommu.strict=1 slab_nomerge init_on_alloc=1 init_on_free=1 pti=on vsyscall=none ia32_emulation=0 page_alloc.shuffle=1 randomize_kstack_offset=on debugfs=off lockdown=confidentiality module.sig_enforce=1#g" /mnt/etc/default/grub
fi

## Add keyfile to the initramfs to avoid double password
if [ "${use_luks}" = '1' ]; then
    dd bs=512 count=4 if=/dev/random of=/mnt/cryptkey/.root.key iflag=fullblock
    chmod 000 /mnt/cryptkey/.root.key
    echo -n "${luks_passphrase}" | cryptsetup luksAddKey /dev/disk/by-partlabel/rootfs /mnt/cryptkey/.root.key -d -
    sed -i 's#FILES=()#FILES=(/cryptkey/.root.key)#g' /mnt/etc/mkinitcpio.conf
    sed -i "s#module\.sig_enforce=1#module.sig_enforce=1 rd.luks.key=/cryptkey/.root.key#g" /mnt/etc/default/grub
fi

## Continue kernel hardening
unpriv curl -s https://raw.githubusercontent.com/secureblue/secureblue/live/files/system/etc/modprobe.d/blacklist.conf | tee /mnt/etc/modprobe.d/blacklist.conf > /dev/null
if [ "${install_mode}" = 'server' ]; then
    unpriv curl -s https://raw.githubusercontent.com/TommyTran732/Linux-Setup-Scripts/main/etc/sysctl.d/99-server.conf | tee /mnt/etc/sysctl.d/99-server.conf > /dev/null
else 
    unpriv curl -s https://raw.githubusercontent.com/TommyTran732/Linux-Setup-Scripts/main/etc/sysctl.d/99-workstation.conf | tee /mnt/etc/sysctl.d/99-workstation.conf > /dev/null
fi

## Setup NTS
unpriv curl -s https://raw.githubusercontent.com/GrapheneOS/infrastructure/refs/heads/main/etc/chrony.conf | tee /mnt/etc/chrony.conf > /dev/null
mkdir -p /mnt/etc/sysconfig
unpriv curl -s https://raw.githubusercontent.com/TommyTran732/Linux-Setup-Scripts/main/etc/sysconfig/chronyd | tee /mnt/etc/sysconfig/chronyd > /dev/null

## Remove nullok from system-auth
sed -i 's/nullok//g' /mnt/etc/pam.d/system-auth

## Harden SSH
## Arch annoyingly does not split openssh-server out so even desktop Arch will have the daemon

unpriv curl -s https://raw.githubusercontent.com/TommyTran732/Linux-Setup-Scripts/main/etc/ssh/ssh_config.d/10-custom.conf | tee /mnt/etc/ssh/ssh_config.d/10-custom.conf > /dev/null
unpriv curl -s https://raw.githubusercontent.com/TommyTran732/Linux-Setup-Scripts/main/etc/ssh/sshd_config.d/10-custom.conf | tee /mnt/etc/ssh/sshd_config.d/10-custom.conf > /dev/null
sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/g' /mnt/etc/ssh/sshd_config.d/10-custom.conf
mkdir -p /mnt/etc/systemd/system/sshd.service.d/
unpriv curl -s https://raw.githubusercontent.com/GrapheneOS/infrastructure/refs/heads/main/etc/systemd/system/sshd.service.d/override.conf | tee /mnt/etc/systemd/system/sshd.service.d/override.conf > /dev/null

## Disable coredump
mkdir -p /mnt/etc/security/limits.d/
unpriv curl -s https://raw.githubusercontent.com/TommyTran732/Linux-Setup-Scripts/main/etc/security/limits.d/30-disable-coredump.conf | tee /mnt/etc/security/limits.d/30-disable-coredump.conf > /dev/null
mkdir -p /mnt/etc/systemd/coredump.conf.d
unpriv curl -s https://raw.githubusercontent.com/TommyTran732/Linux-Setup-Scripts/main/etc/systemd/coredump.conf.d/disable.conf | tee /mnt/etc/systemd/coredump.conf.d/disable.conf > /dev/null

# Disable XWayland
if [ "${install_mode}" = 'desktop' ]; then
    mkdir -p /mnt/etc/systemd/user/org.gnome.Shell@wayland.service.d
    unpriv curl -s https://raw.githubusercontent.com/TommyTran732/Linux-Setup-Scripts/main/etc/systemd/user/org.gnome.Shell%40wayland.service.d/override.conf | tee /mnt/etc/systemd/user/org.gnome.Shell@wayland.service.d/override.conf > /dev/null
fi

# Setup dconf

if [ "${install_mode}" = 'desktop' ]; then
    # This doesn't actually take effect atm - need to investigate

    mkdir -p /mnt/etc/dconf/db/local.d/locks

    unpriv curl -s https://raw.githubusercontent.com/TommyTran732/Linux-Setup-Scripts/main/etc/dconf/db/local.d/locks/automount-disable | tee /mnt/etc/dconf/db/local.d/locks/automount-disable > /dev/null
    unpriv curl -s https://raw.githubusercontent.com/TommyTran732/Linux-Setup-Scripts/main/etc/dconf/db/local.d/locks/privacy | tee /mnt/etc/dconf/db/local.d/locks/privacy > /dev/null

    unpriv curl -s https://raw.githubusercontent.com/TommyTran732/Linux-Setup-Scripts/main/etc/dconf/db/local.d/adw-gtk3-dark | tee /mnt/etc/dconf/db/local.d/adw-gtk3-dark > /dev/null
    unpriv curl -s https://raw.githubusercontent.com/TommyTran732/Linux-Setup-Scripts/main/etc/dconf/db/local.d/automount-disable | tee /mnt/etc/dconf/db/local.d/automount-disable > /dev/null
    unpriv curl -s https://raw.githubusercontent.com/TommyTran732/Linux-Setup-Scripts/main/etc/dconf/db/local.d/button-layout | tee /mnt/etc/dconf/db/local.d/button-layout > /dev/null
    unpriv curl -s https://raw.githubusercontent.com/TommyTran732/Linux-Setup-Scripts/main/etc/dconf/db/local.d/prefer-dark | tee /mnt/etc/dconf/db/local.d/prefer-dark > /dev/null
    unpriv curl -s https://raw.githubusercontent.com/TommyTran732/Linux-Setup-Scripts/main/etc/dconf/db/local.d/privacy | tee /mnt/etc/dconf/db/local.d/privacy > /dev/null
    unpriv curl -s https://raw.githubusercontent.com/TommyTran732/Linux-Setup-Scripts/main/etc/dconf/db/local.d/touchpad | tee /mnt/etc/dconf/db/local.d/touchpad > /dev/null
fi

## ZRAM configuration
unpriv curl -s https://raw.githubusercontent.com/TommyTran732/Linux-Setup-Scripts/main/etc/systemd/zram-generator.conf | tee /mnt/etc/systemd/zram-generator.conf > /dev/null

## Setup unbound

if [ "${install_mode}" = 'server' ]; then
    unpriv curl -s https://raw.githubusercontent.com/TommyTran732/Arch-Setup-Script/main/etc/unbound/unbound.conf | tee /mnt/etc/unbound/unbound.conf > /dev/null
fi

## Setup Networking

if [ "${install_mode}" = 'desktop' ]; then
    unpriv curl -s https://raw.githubusercontent.com/TommyTran732/Linux-Setup-Scripts/main/etc/NetworkManager/conf.d/00-macrandomize.conf | tee /mnt/etc/NetworkManager/conf.d/00-macrandomize.conf > /dev/null
    unpriv curl -s https://raw.githubusercontent.com/TommyTran732/Linux-Setup-Scripts/main/etc/NetworkManager/conf.d/01-transient-hostname.conf | tee /mnt/etc/NetworkManager/conf.d/01-transient-hostname.conf > /dev/null
fi

if [ "${network_daemon}" = 'networkmanager' ]; then
    mkdir -p /mnt/etc/systemd/system/NetworkManager.service.d/
    unpriv curl -s https://gitlab.com/divested/brace/-/raw/master/brace/usr/lib/systemd/system/NetworkManager.service.d/99-brace.conf | tee /mnt/etc/systemd/system/NetworkManager.service.d/99-brace.conf > /dev/null
fi

if [ "${network_daemon}" = 'systemd-networkd' ]; then
    # arch-iso has working networking, booted does not
    cp -ap /etc/systemd/network/20* /mnt/etc/systemd/network/ > /dev/null
fi

## Configuring the system
arch-chroot /mnt /bin/bash -e <<EOF

    # Setting up timezone
    # Temporarily hardcoding here
    ln -sf /usr/share/zoneinfo/Etc/UTC /etc/localtime

    # Setting up clock
    hwclock --systohc

    # Generating locales
    locale-gen

    # Generating a new initramfs
    chmod 600 /boot/initramfs-linux*
    mkinitcpio -P

    # Installing GRUB
    grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB --disable-shim-lock

    # Creating grub config file
    grub-mkconfig -o /boot/grub/grub.cfg

    # Adding user with sudo privilege
    useradd -c "$fullname" -m "$username"
    usermod -aG wheel "$username"

    if [ "${install_mode}" = 'desktop' ]; then
        # Setting up dconf
        dconf update
    fi

    # Snapper configuration
    umount /.snapshots
    rm -r /.snapshots
    snapper --no-dbus -c root create-config /
    btrfs subvolume delete /.snapshots
    mkdir /.snapshots
    mount -a
    chmod 750 /.snapshots
EOF

## Set user password.
[ -n "$username" ] && echo "Setting user password for ${username}." && echo -e "${user_password}\n${user_password}" | arch-chroot /mnt passwd "$username"

## Give wheel user sudo access.
sed -i 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/g' /mnt/etc/sudoers

## Enable services
systemctl enable apparmor --root=/mnt
systemctl enable chronyd --root=/mnt
systemctl enable firewalld --root=/mnt
systemctl enable fstrim.timer --root=/mnt
systemctl enable grub-btrfsd.service --root=/mnt
systemctl enable reflector.timer --root=/mnt
systemctl enable snapper-timeline.timer --root=/mnt
systemctl enable snapper-cleanup.timer --root=/mnt
systemctl enable systemd-oomd --root=/mnt
systemctl disable systemd-timesyncd --root=/mnt

if [ "${network_daemon}" = 'networkmanager' ]; then
    systemctl enable NetworkManager --root=/mnt
else 
    systemctl enable systemd-networkd --root=/mnt
fi

if [ "${install_mode}" = 'desktop' ]; then
    systemctl enable gdm --root=/mnt
    rm /mnt/etc/resolv.conf
    ln -s /run/systemd/resolve/stub-resolv.conf /mnt/etc/resolv.conf
    systemctl enable systemd-resolved --root=/mnt
fi

if [ "${install_mode}" = 'server' ]; then
    systemctl enable sshd --root=/mnt
    systemctl enable unbound --root=/mnt
fi

## Set umask to 077.
sed -i 's/^UMASK.*/UMASK 077/g' /mnt/etc/login.defs
sed -i 's/^HOME_MODE/#HOME_MODE/g' /mnt/etc/login.defs
sed -i 's/umask 022/umask 077/g' /mnt/etc/bash.bashrc

# Finish up
echo "Done, you may now wish to reboot (further changes can be done by chrooting into /mnt)."
exit
