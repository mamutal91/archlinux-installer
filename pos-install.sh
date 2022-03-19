#!/usr/bin/env bash

# Get the device uuid
SSD2_UUID=$(blkid $SSD2 | awk -F '"' '{print $2}')
SSD3_UUID=$(blkid $SSD3 | awk -F '"' '{print $2}')

# Set user and hostname
useradd -m -G wheel -s /bin/bash $USERNAME
mkdir -p /home/$USERNAME
echo $HOSTNAME > /etc/hostname

# Configure hosts
echo "127.0.0.1	localhost
::1		localhost
127.0.1.1	modinx" | tee /etc/hosts

# Discover the best mirros to download packages and update pacman configs
reflector --verbose --country 'Brazil' --latest 5 --sort rate --save /etc/pacman.d/mirrorlist
sed -i "/\[multilib\]/,/Include/"'s/^#//' /etc/pacman.conf
sed -i 's/#UseSyslog/UseSyslog/' /etc/pacman.conf && \
sed -i 's/#Color/Color\\\nILoveCandy/' /etc/pacman.conf && \
sed -i 's/Color\\/Color/' /etc/pacman.conf && \
sed -i 's/#TotalDownload/TotalDownload/' /etc/pacman.conf && \
sed -i 's/#CheckSpace/CheckSpace/' /etc/pacman.conf
sed -i "s/#VerbosePkgLists/VerbosePkgLists/g" /etc/pacman.conf
sed -i "s/#ParallelDownloads = 5/ParallelDownloads = 10/g" /etc/pacman.conf

# Setup locate and time
echo "KEYMAP=br-abnt2" > /etc/vconsole.conf
sed -i "s/#pt_BR.UTF-8 UTF-8/pt_BR.UTF-8 UTF-8/g" /etc/locale.gen
sed -i "s/#pt_BR ISO-8859-1/pt_BR ISO-8859-1/g" /etc/locale.gen
sed -i "s/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/g" /etc/locale.gen
sed -i "s/#en_US ISO-8859-1/en_US ISO-8859-1/g" /etc/locale.gen
echo "LANG=pt_BR.UTF-8" > /etc/locale.conf
locale-gen
ln -sf /usr/share/zoneinfo/America/Sao_Paulo /etc/localtime
hwclock --systohc

# SSHD
sed -i "s/#AllowTcpForwarding/AllowTcpForwarding/g" /etc/ssh/sshd_config
sed -i "s/AllowTcpForwarding no/AllowTcpForwarding yes/g" /etc/ssh/sshd_config

# Generate the initramfs
sed -i "s/BINARIES=()/BINARIES=(btrfs)/g" /etc/mkinitcpio.conf
sed -i "s/block/block encrypt/g" /etc/mkinitcpio.conf

sed -i 's/BINARIES=()/BINARIES=("\/usr\/bin\/btrfs")/' /etc/mkinitcpio.conf
#sed -i 's/MODULES=()/MODULES=(amdgpu)/' /etc/mkinitcpio.conf
sed -i 's/#COMPRESSION="lz4"/COMPRESSION="lz4"/' /etc/mkinitcpio.conf
sed -i 's/#COMPRESSION_OPTIONS=()/COMPRESSION_OPTIONS=(-9)/' /etc/mkinitcpio.conf
sed -i 's/^HOOKS.*/HOOKS=(base udev systemd autodetect modconf block sd-encrypt encrypt filesystems keyboard fsck)/' /etc/mkinitcpio.conf

mkinitcpio -p linux-lts
mkinitcpio -p linux

# Optimize Makepkg
sed -i 's/^CFLAGS.*/CFLAGS="-march=native -mtune=native -O2 -pipe -fstack-protector-strong --param=ssp-buffer-size=4 -fno-plt"/' /etc/makepkg.conf
sed -i 's/^CXXFLAGS.*/CXXFLAGS="-march=native -mtune=native -O2 -pipe -fstack-protector-strong --param=ssp-buffer-size=4 -fno-plt"/' /etc/makepkg.conf
sed -i 's/^#RUSTFLAGS.*/RUSTFLAGS="-C opt-level=2 -C target-cpu=native"/' /etc/makepkg.conf
sed -i 's/^#BUILDDIR.*/BUILDDIR=\/tmp\/makepkg/' /etc/makepkg.conf
sed -i 's/^#MAKEFLAGS.*/MAKEFLAGS="-j$(getconf _NPROCESSORS_ONLN) --quiet"/' /etc/makepkg.conf
sed -i 's/^COMPRESSGZ.*/COMPRESSGZ=(pigz -c -f -n)/' /etc/makepkg.conf
sed -i 's/^COMPRESSBZ2.*/COMPRESSBZ2=(pbzip2 -c -f)/' /etc/makepkg.conf
sed -i 's/^COMPRESSXZ.*/COMPRESSXZ=(xz -T "$(getconf _NPROCESSORS_ONLN)" -c -z --best -)/' /etc/makepkg.conf
sed -i 's/^COMPRESSZST.*/COMPRESSZST=(zstd -c -z -q --ultra -T0 -22 -)/' /etc/makepkg.conf
sed -i 's/^COMPRESSLZ.*/COMPRESSLZ=(lzip -c -f)/' /etc/makepkg.conf
sed -i 's/^COMPRESSLRZ.*/COMPRESSLRZ=(lrzip -9 -q)/' /etc/makepkg.conf
sed -i 's/^COMPRESSLZO.*/COMPRESSLZO=(lzop -q --best)/' /etc/makepkg.conf
sed -i 's/^COMPRESSZ.*/COMPRESSZ=(compress -c -f)/' /etc/makepkg.conf
sed -i 's/^COMPRESSLZ4.*/COMPRESSLZ4=(lz4 -q --best)/' /etc/makepkg.conf

# Setup the bootloader
bootctl --path=/boot install

# Generate the arch linux entry config
mkdir -p /boot/loader/entries
cat > /boot/loader/entries/arch.conf << EOF
title   Arch Linux
linux   /vmlinuz-linux
initrd  /initramfs-linux.img
options rd.luks.name=${SSD3_UUID}=system root=/dev/mapper/system rootflags=subvol=root rd.luks.options=discard rw
EOF

# Generate the loader config
cat > /boot/loader/loader.conf << EOF
default  arch.conf
timeout  4
console-mode max
editor   no
EOF

# Configure grub
sed -i 's/GRUB_DEFAULT=0/GRUB_DEFAULT=saved/g' /etc/default/grub
sed -i -e 's/GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 quiet"/GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 quiet splash acpi_backlight=vendor"/g' /etc/default/grub
sed -i -e 's/GRUB_CMDLINE_LINUX=""/GRUB_CMDLINE_LINUX="cryptdevice=UUID='${SSD3_UUID}':cryptsystem"/g' /etc/default/grub
sed -i 's/#GRUB_ENABLE_CRYPTODISK=y/GRUB_ENABLE_CRYPTODISK=y/g' /etc/default/grub
sed -i 's/#GRUB_SAVEDEFAULT=true/GRUB_SAVEDEFAULT=true/g' /etc/default/grub
sed -i 's/#GRUB_DISABLE_SUBMENU=y/GRUB_DISABLE_SUBMENU=y/g' /etc/default/grub
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=grub
grub-mkconfig -o /boot/grub/grub.cfg

# Configure systemd for laptop's
sed -i 's/#HandleLidSwitch=suspend/HandleLidSwitch=ignore/g' /etc/systemd/logind.conf
sed -i 's/#NAutoVTs=6/NAutoVTs=6/g' /etc/systemd/logind.conf

# Services
systemctl disable NetworkManager
systemctl enable dhcpcd
systemctl enable iwd

# Sudo configs
sed -i "s/root ALL=(ALL:ALL) ALL/root ALL=(ALL:ALL) NOPASSWD: ALL\n${USERNAME} ALL=(ALL:ALL) NOPASSWD: ALL/g" /etc/sudoers
sed -i 's/^# %wheel ALL=(ALL:ALL) NOPASSWD: ALL$/%wheel ALL=(ALL:ALL) NOPASSWD: ALL/' /etc/sudoers
echo "Defaults timestamp_timeout=0" >> /etc/sudoers

# My notebook
mountStorages() {
  # Storage 2
  STORAGE_HDD_UUID=$(blkid $STORAGE_HDD | awk -F '"' '{print $2}')
  mkdir -p /mnt/hdd
  echo -e "\nhdd UUID=$STORAGE_HDD_UUID /root/keyHDD luks" >> /etc/crypttab
  echo -e "\n# HDD" >> /etc/fstab
  echo "/dev/mapper/hdd  /mnt/hdd     btrfs    defaults        0       2" >> /etc/fstab
  dd if=/dev/urandom of=/root/keyHDD bs=1024 count=4
  chmod 0400 /root/keyHDD
  clear
  echo "Type crypt password $STORAGE_HDD"
  cryptsetup -v luksAddKey $STORAGE_HDD /root/keyHDD
}

if [[ $USERNAME == mamutal91 ]]; then
  mountStorages
fi

# Define passwords
clear
echo "Type user password $USERNAME"
passwd $USERNAME && clear
echo "Type user password root"
passwd root

if [[ $USERNAME == mamutal91 ]]; then
  git clone https://github.com/mamutal91/dotfiles /home/mamutal91/.dotfiles
  sed -i 's/https/ssh/g' /home/mamutal91/.dotfiles/.git/config
  sed -i 's/github/git@github/g' /home/mamutal91/.dotfiles/.git/config
fi

chown -R $USERNAME:$USERNAME /home/$USERNAME
