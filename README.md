# auto-luks-zfs
Automatic setup of luks + zfs

# disclaimer
Barely tested.
Will wipe at least the target disk.
Use at own risk.

# how to
1. boot into ubuntu 16.04 live
2. make sure target disk it not in use (should also be unmounted)
3. run install.sh with root `sudo curl https://raw.githubusercontent.com/VegarM/auto-luks-zfs/master/install.sh | bash`

# references
Based on https://github.com/zfsonlinux/zfs/wiki/Ubuntu-16.04-Root-on-ZFS
