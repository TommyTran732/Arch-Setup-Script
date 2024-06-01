#!/bin/bash

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

# Install new grub version
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB --modules="normal test efi_gop efi_uga search echo linux all_video gfxmenu gfxterm_background gfxterm_menu gfxterm loadenv configfile gzio part_gpt cryptodisk luks gcry_rijndael gcry_sha256 btrfs" --disable-shim-lock

# Disable root subvol pinning.
## This is **extremely** important, as snapper expects to be able to set the default btrfs subvol.
# shellcheck disable=SC2016
sed -i 's/rootflags=subvol=${rootsubvol}//g' /mnt/etc/grub.d/10_linux
# shellcheck disable=SC2016
sed -i 's/rootflags=subvol=${rootsubvol}//g' /mnt/etc/grub.d/20_linux_xen

# Generate grub config
grub-mkconfig -o /boot/grub/grub.cfg