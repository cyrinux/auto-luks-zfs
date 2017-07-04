echo -e "Velkommen :)\n"

echo "Select disk:"
select CHOICE_DISK in $(ls /dev/disk/by-id/ | grep -v "\-part");
do
  echo "Selected ${CHOICE_DISK}"
  break
done


read -es -p "Passphrase: " CHOICE_PASSPHRASE && echo ""
read -es -p "Root passord: " CHOICE_ROOTPW && echo ""
read -e  -p "Hostname: " CHOICE_HOSTNAME && echo ""

# Install requirements
apt update --yes 
apt install --yes mdadm debootstrap gdisk zfsutils-linux


sleep 2 # Zero mdadm superblock to prevent future corruption if mdadm attempt to rebuildan old array.
mdadm --zero-superblock --force /dev/disk/by-id/${CHOICE_DISK}

sleep 2 # Partition disks
sgdisk     --clear               /dev/disk/by-id/${CHOICE_DISK}
sgdisk     -n3:1M:+512M -t3:EF00 /dev/disk/by-id/${CHOICE_DISK}
sgdisk     -n9:-8M:0    -t9:BF07 /dev/disk/by-id/${CHOICE_DISK}
sgdisk     -n4:0:+512M  -t4:8300 /dev/disk/by-id/${CHOICE_DISK}
sgdisk     -n1:0:0      -t1:8300 /dev/disk/by-id/${CHOICE_DISK}

sleep 2 # Setup luks
echo -n "${CHOICE_PASSPHRASE}" | cryptsetup luksFormat -c aes-xts-plain64 -s 256 -h sha256 /dev/disk/by-id/${CHOICE_DISK}-part1 -

echo -n "${CHOICE_PASSPHRASE}" | cryptsetup luksOpen /dev/disk/by-id/${CHOICE_DISK}-part1 luks1 -

sleep 2 # Create zfs pool
zpool create \
      -o ashift=12 \
      -O atime=off \
      -O canmount=off \
      -O compression=lz4 \
      -O normalization=formD \
      -O mountpoint=/ \
      -R /mnt \
      rpool /dev/mapper/luks1

sleep 2 # Create filesystem dataset to act as a container
zfs create -o canmount=off -o mountpoint=none rpool/ROOT

sleep 2 # Create a filesystem dataset for the root filesystem of the ubuntu system
zfs create -o canmount=noauto -o mountpoint=/ rpool/ROOT/ubuntu
zfs mount rpool/ROOT/ubuntu

sleep 2 # Create datasets
zfs create                 -o setuid=off              rpool/home
zfs create -o mountpoint=/root                        rpool/home/root
zfs create -o canmount=off -o setuid=off  -o exec=off rpool/var
zfs create -o com.sun:auto-snapshot=false             rpool/var/cache
zfs create                                            rpool/var/log
zfs create                                            rpool/var/spool
zfs create -o com.sun:auto-snapshot=false -o exec=on  rpool/var/tmp
zfs create                                            rpool/srv
zfs create                                            rpool/var/games

sleep 2 # Create unencrypted boot partition
mke2fs -t ext2 /dev/disk/by-id/${CHOICE_DISK}-part4
mkdir /mnt/boot
mount /dev/disk/by-id/${CHOICE_DISK}-part4 /mnt/boot

sleep 2 # Install base system
chmod 1777 /mnt/var/tmp
debootstrap xenial /mnt
zfs set devices=off rpool

echo ${CHOICE_HOSTNAME} > /mnt/etc/hostname
echo 127.0.1.1       ${CHOICE_HOSTNAME} >> /mnt/etc/hosts

mount --rbind /dev  /mnt/dev
mount --rbind /proc /mnt/proc
mount --rbind /sys  /mnt/sys

# Enter chroot
cat << EOF | chroot /mnt
# Inside chroot
echo "deb http://archive.ubuntu.com/ubuntu xenial main universe
deb-src http://archive.ubuntu.com/ubuntu xenial main universe

deb http://security.ubuntu.com/ubuntu xenial-security main universe
deb-src http://security.ubuntu.com/ubuntu xenial-security main universe

deb http://archive.ubuntu.com/ubuntu xenial-updates main universe
deb-src http://archive.ubuntu.com/ubuntu xenial-updates main universe" > /etc/apt/sources.list

ln -s /proc/self/mounts /etc/mtab
ln -s /dev/mapper/luks1 /dev/luks1

apt update

# Locale
locale-gen en_US.UTF-8
echo 'LANG="en_US.UTF-8"' > /etc/default/locale
echo "Europe/Oslo" > /etc/timezone
dpkg-reconfigure -f noninteractive tzdata

# Pakker
apt update && apt -y upgrade && apt -y dist-upgrade && apt autoremove
apt install --yes ubuntu-minimal
apt install --yes --no-install-recommends linux-image-generic
apt install --yes zfs-initramfs

# Crypt
echo UUID=$(blkid -s UUID -o value \
      /dev/disk/by-id/${CHOICE_DISK}-part4) \
      /boot ext2 defaults 0 2 >> /etc/fstab

apt install --yes cryptsetup

echo luks1 UUID=$(blkid -s UUID -o value \
      /dev/disk/by-id/${CHOICE_DISK}-part1) none \
      luks,discard,initramfs > /etc/crypttab


echo 'ENV{DM_NAME}!="", SYMLINK+="\$env{DM_NAME}"' > /etc/udev/rules.d/99-local.rules
echo 'ENV{DM_NAME}!="", SYMLINK+="dm-name-\$env{DM_NAME}"' >> /etc/udev/rules.d/99-local.rules


echo "/dev/disk/by-id/${CHOICE_DISK}  /  zfs  defaults 0 0" >> /etc/fstab

apt -y install dmsetup cryptsetup zfs-initramfs
apt -y --no-install-recommends install linux-image-generic linux-headers-generic linux-firmware linux-tools-generic

# Initramfs
apt install dosfstools
mkdosfs -F 32 -n EFI /dev/disk/by-id/${CHOICE_DISK}-part3
mkdir /boot/efi
echo PARTUUID=$(blkid -s PARTUUID -o value \
    /dev/disk/by-id/${CHOICE_DISK}-part3) \
    /boot/efi vfat defaults 0 1 >> /etc/fstab
mount /boot/efi
apt install --yes grub-efi-amd64

addgroup --system lpadmin
addgroup --system sambashare

echo -e "${CHOICE_ROOTPW}\n${CHOICE_ROOTPW}" | (passwd root)

# Fix filesystem mount ordering
zfs set mountpoint=legacy rpool/var/log
zfs set mountpoint=legacy rpool/var/tmp

echo "rpool/var/log /var/log zfs defaults 0 0
rpool/var/tmp /var/tmp zfs defaults 0 0" >> /etc/fstab

# Grub verify
grub-probe /
update-initramfs -c -k all

# Install grub
sed -i.bkp -e '/GRUB_HIDDEN_TIMEOUT/ s/^#*/#/' -e '/GRUB_CMDLINE_LINUX_DEFAULT/ s/".*"//' -e '/GRUB_TERMINAL=console/ s/^#//' /etc/default/grub
update-grub
grub-install --target=x86_64-efi --efi-directory=/boot/efi \
      --bootloader-id=ubuntu --recheck --no-floppy

# Verify grub module got installed
ls /boot/grub/*/zfs.mod

# Create snapshot of install state
zfs snapshot rpool/ROOT/ubuntu@install

lsinitramfs /boot/initrd.img-*-generic |grep -E "cryptsetup$|cryptroot$"

EOF

# Clean up after chroot
mount | grep -v zfs | tac | awk '/\/mnt/ {print $3}' | xargs -i{} umount -lf {}
zpool export rpool
cryptsetup luksClose luks1
sync
echo "Now you can reboot :)"
