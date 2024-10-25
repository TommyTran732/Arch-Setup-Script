#!/bin/sh

# Copyright (C) 2021-2024 Thien Tran
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

sudo pacman -S --noconfirm sbctl
sudo sbctl create-keys
sudo mkinitcpio -P

# Install new grub version
sudo grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB --disable-shim-lock

# Sign grub
sudo sbctl sign-all

# Disable root subvol pinning.
## This is **extremely** important, as snapper expects to be able to set the default btrfs subvol.
# shellcheck disable=SC2016
sudo sed -i 's/rootflags=subvol=${rootsubvol}//g' /mnt/etc/grub.d/10_linux
# shellcheck disable=SC2016
sudo sed -i 's/rootflags=subvol=${rootsubvol}//g' /mnt/etc/grub.d/20_linux_xen

# Generate grub config
sudo grub-mkconfig -o /boot/grub/grub.cfg