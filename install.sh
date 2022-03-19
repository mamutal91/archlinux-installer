#!/usr/bin/env bash

read -r -p "You username? " USERNAME
[[ -z $USERNAME ]] && USERNAME=mamutal91 || USERNAME=$USERNAME
echo -e "$USERNAME\n"
read -r -p "You hostname? " HOSTNAME
[[ -z $HOSTNAME ]] && HOSTNAME=modinx || HOSTNAME=$HOSTNAME
echo -e "$HOSTNAME\n"

clear

if [[ $USERNAME == mamutal91 ]]; then
  SSD=/dev/nvme0n1 # ssd m2 nvme
  SSD1=/dev/nvme0n1p1 # EFI (boot)
  SSD2=/dev/nvme0n1p2 # cryptsystem
  STORAGE_HDD=/dev/sda # hdd"
  askFormatStorages() {
  }
  askFormatStorages
else
  echo -e "Specify disks!!!
  Examples:\n\n
  SSD=/dev/nvme0n1 # ssd m2 nvme
  SSD1=/dev/nvme0n1p1 # EFI (boot)
  SSD2=/dev/nvme0n1p2 # cryptsystem
  STORAGE_NVME=/dev/sdb # ssd
  STORAGE_HDD=/dev/sda # hdd"
  exit 0
fi

[[ $USERNAME == mamutal91 ]] && git config --global user.email "mamutal91@gmail.com" && git config --global user.name "Alexandre Rangel"

formatStorages() {
  # Format and encrypt the hdd partition 1
  if [[ $formatHDD == true ]]; then
    sgdisk -g --clear \
      --new=1:0:0       --typecode=3:8300 --change-name=1:hdd \
      $STORAGE_HDD
    cryptsetup luksFormat --align-payload=8192 -s 256 -c aes-xts-plain64 $STORAGE_HDD
    if [[ $? -eq 0 ]]; then
      echo "cryptsetup luksFormat SUCCESS ${STORAGE_HDD}"
    else
      echo "cryptsetup luksFormat FAILURE ${STORAGE_HDD}"
      exit 1
    fi
    cryptsetup luksOpen $STORAGE_HDD hdd
    mkfs.btrfs --force --label hdd /dev/mapper/hdd
    cryptsetup luksOpen $STORAGE_HDD hdd
  fi
}

format() {
  echo -n "Você deseja formatar o ${STORAGE_HDD} (hdd)? (y/n)? "; read answer
  if [[ $answer != ${answer#[Yy]} ]]; then
    echo -n "Você tem certeza? (y/n)? "; read answer
    if [[ $answer != ${answer#[Yy]} ]]; then
      formatStorages
    else
      echo No format ${STORAGE_HDD}
    fi
  else
    echo No format ${STORAGE_HDD}
  fi

  # Start!!!
  # Format the drive
  sgdisk --zap-all $SSD
  sgdisk -g --clear \
    --new=1:0:+1GiB   --typecode=1:ef00 --change-name=1:EFI \
    --new=2:0:0       --typecode=2:8300 --change-name=2:cryptsystem \
    $SSD
    if [[ $? -eq 0 ]]; then
      echo "sgdisk SUCCESS"
  else
      echo "sgdisk FAILURE"
      exit 1
  fi

  # Encrypt the system partition
  cryptsetup luksFormat --perf-no_read_workqueue --perf-no_write_workqueue --type luks2 --cipher aes-xts-plain64 --key-size 512 --iter-time 2000 --pbkdf argon2id --hash sha3-512 $SSD2
  if [[ $? -eq 0 ]]; then
    echo "cryptsetup luksFormat SUCCESS"
  else
    echo "cryptsetup luksFormat FAILURE"
    exit 1
  fi
  cryptsetup --allow-discards --perf-no_read_workqueue --perf-no_write_workqueue --persistent open $SSD2 crypt

  # Format the partitions
  mkfs.vfat -F32 -n "EFI" $SSD1
  mkfs.btrfs -L Arch -f /dev/mapper/crypt

  # Create btrfs subvolumes
  mount /dev/mapper/crypt /mnt
  btrfs sub create /mnt/@ && \
  btrfs sub create /mnt/@home && \
  btrfs sub create /mnt/@tmp && \
  btrfs sub create /mnt/@snapshots && \
  btrfs sub create /mnt/@btrfs && \
  btrfs sub create /mnt/@log && \
  btrfs sub create /mnt/@cache
  umount /mnt

  # Mount partitions
  mount -o noatime,compress-force=zstd,commit=120,space_cache=v2,ssd,discard=async,autodefrag,subvol=@ /dev/mapper/crypt /mnt
  mkdir -p /mnt/{boot,home,var/cache,var/log,.snapshots,btrfs,var/tmp,}
  mount -o noatime,compress-force=zstd,commit=120,space_cache=v2,ssd,discard=async,autodefrag,subvol=@home /dev/mapper/crypt /mnt/home  && \
  mount -o nodev,nosuid,noexec,noatime,compress-force=zstd,commit=120,space_cache=v2,ssd,discard=async,autodefrag,subvol=@tmp /dev/mapper/crypt /mnt/var/tmp && \
  mount -o nodev,nosuid,noexec,noatime,compress-force=zstd,commit=120,space_cache=v2,ssd,discard=async,autodefrag,subvol=@log /dev/mapper/crypt /mnt/var/log && \
  mount -o nodev,nosuid,noexec,noatime,compress-force=zstd,commit=120,space_cache=v2,ssd,discard=async,autodefrag,subvol=@cache /dev/mapper/crypt /mnt/var/cache && \
  mount -o noatime,compress-force=zstd,commit=120,space_cache=v2,ssd,discard=async,autodefrag,subvol=@snapshots /dev/mapper/crypt /mnt/.snapshots && \
  mount -o noatime,compress-force=zstd,commit=120,space_cache=v2,ssd,discard=async,autodefrag,subvolid=5 /dev/mapper/crypt /mnt/btrfs

  mkdir -p /mnt/boot
  mount -o nodev,nosuid,noexec $SS1 /mnt/boot

  # Discover the best mirros to download packages
  reflector --verbose --country 'Brazil' --latest 5 --sort rate --save /etc/pacman.d/mirrorlist
  sed -i "/\[multilib\]/,/Include/"'s/^#//' /etc/pacman.conf
  sed -i "s/#Color/Color/g" /etc/pacman.conf
  sed -i "s/#UseSyslog/UseSyslog/g" /etc/pacman.conf
  sed -i "s/#VerbosePkgLists/VerbosePkgLists/g" /etc/pacman.conf
  sed -i "s/#ParallelDownloads = 5/ParallelDownloads = 10/g" /etc/pacman.conf

  # Install base system and some basic tools
  pacstrap /mnt --noconfirm \
    base base-devel bash-completion amd-ucode \
    linux-lts linux-lts-headers linux linux-headers \
    linux-firmware linux-firmware-whence \
    mkinitcpio pacman-contrib systemd-swap refind \
    linux-api-headers util-linux util-linux-libs lib32-util-linux \
    btrfs-progs efibootmgr efitools gptfdisk grub grub-btrfs dm-crypt ntfs-3g exfat-utils \
    iwd networkmanager dhcpcd sudo grub nano git reflector wget openssh zsh git curl wget

  # Generate fstab entries
  genfstab -U /mnt > /mnt/etc/fstab

  # Copy wifi connection to the system
  mkdir -p /mnt/var/lib/iwd
  chmod 700 /mnt/var/lib/iwd
  cp -rf /var/lib/iwd/*.psk /mnt/var/lib/iwd

  # Arch Chroot
  sed -i "2i USERNAME=${USERNAME}" pos-install.sh
  sed -i "3i HOSTNAME=${HOSTNAME}" pos-install.sh
  sed -i "4i SSD2=${SSD2}" pos-install.sh
  sed -i "5i STORAGE_HDD=${STORAGE_HDD}" pos-install.sh
  chmod +x pos-install.sh && cp -rf pos-install.sh /mnt && clear
  sleep 5
  arch-chroot /mnt ./pos-install.sh
  if [[ $? -eq 0 ]]; then
    umount -R /mnt
    echo -e "\n\nFinished SUCCESS\n"
    read -r -p "Reboot now? [Y/n]" confirmReboot
    if [[ ! $confirmReboot =~ ^(n|N) ]]; then
      reboot
    fi
  else
    echo "pos-install FAILURE"
    exit 1
  fi
}

recovery() {
  cryptsetup open $SSD3 system
  cryptsetup open --type plain --key-file /dev/urandom $SSD2 swap
  mkswap -L swap /dev/mapper/swap
  swapon -L swap
  o=defaults,x-mount.mkdir
  o_btrfs=$o,compress=zstd,ssd,noatime
  mount -t btrfs -o subvol=root,$o_btrfs LABEL=system /mnt
  mount -t btrfs -o subvol=home,$o_btrfs LABEL=system /mnt/home
  mount -t btrfs -o subvol=snapshots,$o_btrfs LABEL=system /mnt/.snapshots
  mount $SSD1 /mnt/boot
  sleep 5
  arch-chroot /mnt
}

if [[ ${1} == "recovery" ]]; then
  recovery
else
  format
fi
