#!/bin/bash

pacman -S --noconfirm sbsigntools efitools openssl
mkdir -p /etc/efi-keys
cd /etc/efi-keys || exit
curl -L -O https://www.rodsbooks.com/efi-bootloaders/mkkeys.sh
chmod +x mkkeys.sh
./mkkeys.sh

chmod -R g-rwx /etc/efi-keys
chmod -R o-rwx /etc/efi-keys

if [ -f /boot/vmlinuz-linux ]; then
	sbsign --key db.key --cert db.crt --output /boot/vmlinuz-linux /boot/vmlinuz-linux
fi 

if [ -f /boot/vmlinuz-linux-lts ]; then
	sbsign --key db.key --cert db.crt --output /boot/vmlinuz-linux-lts /boot/vmlinuz-linux-lts
fi 

if [ -f /boot/vmlinuz-linux-hardened ]; then
        sbsign --key db.key --cert db.crt --output /boot/vmlinuz-linux-hardened /boot/vmlinuz-linux-hardened
fi        

if [ -f /boot/vmlinuz-linux-zen ]; then
        sbsign --key db.key --cert db.crt --output /boot/vmlinuz-linux-zen /boot/vmlinuz-linux-zen
fi

cp /usr/share/libalpm/hooks/90-mkinitcpio-install.hook /etc/pacman.d/hooks/90-mkinitcpio-install.hook
sed -i 's#Exec = /usr/share/libalpm/scripts/mkinitcpio-install#Exec = /usr/local/share/libalpm/scripts/mkinitcpio-install#g' /etc/pacman.d/hooks/90-mkinitcpio-install.hook

cp /usr/share/libalpm/scripts/mkinitcpio-install /usr/local/share/libalpm/scripts/mkinitcpio-install
sed -i 's#install -Dm644 "${line}" "/boot/vmlinuz-${pkgbase}"#sbsign --key /etc/efi-keys/DB.key --cert /etc/efi-keys/DB.crt --output "/boot/vmlinuz-${pkgbase}" "${line}"#g' /usr/local/share/libalpm/scripts/mkinitcpio-install

mkdir -p /etc/secureboot/keys/{db,dbx,KEK,PK}
ln -s /etc/efi-keys/DB.auth /etc/secureboot/keys/db/DB.auth
ln -s /etc/efi-keys/KEK.auth /etc/secureboot/keys/KEK/KEK.auth
ln -s /etc/efi-keys/PK.auth /etc/secureboot/keys/PK/PK.auth

sbkeysync --verbose --pk

chmod -R g-rwx /etc/secureboot
chmod -R g-rwx /etc/secureboot

grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB --modules="normal test efi_gop efi_uga search echo linux all_video gfxmenu gfxterm_background gfxterm_menu gfxterm loadenv configfile gzio part_gpt cryptodisk luks gcry_rijndael gcry_sha256 btrfs tpm" --disable-shim-lock
sbsign --key /etc/efi-keys/DB.key --cert /etc/efi-keys/DB.crt --output /boot/efi/EFI/GRUB/grubx64.efi /boot/efi/EFI/GRUB/grubx64.efi 
grub-mkconfig -o /boot/grub/grub.cfg

cat << EOF >> /etc/pacman.d/hooks/grub.hook
[Trigger]
Operation=Install
Operation=Upgrade
Type=Package
Target=grub

[Action]
Description=Update grubx64.efi
Depends=grub
When=PostTransaction
NeedsTargets
Exec=/bin/bash -c 'grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB --modules="normal test efi_gop efi_uga search echo linux all_video gfxmenu gfxterm_background gfxterm_menu gfxterm loadenv configfile gzio part_gpt cryptodisk luks gcry_rijndael gcry_sha256 btrfs tpm" --disable-shim-lock && /usr/bin/sbsign --key /etc/efi-keys/DB.key --cert /etc/efi-keys/DB.crt --output /boot/efi/EFI/GRUB/grubx64.efi /boot/efi/EFI/GRUB/grubx64.efi && /usr/bin/sed -i 's#rootflags=subvol=${rootsubvol} ##g' /etc/grub.d/10_linux && /usr/bin/sed -i 's#rootflags=subvol=${rootsubvol} ##g' /etc/grub.d/20_linux_xen && /usr/bin/grub-mkconfig -o /boot/grub/grub.cfg'
EOF

chmod 600 /etc/pacman.d/hooks/*
