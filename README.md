# auto-luks-zfs
Automatic setup of luks + zfs

## Ddisclaimer
- Barely tested.
- Will wipe at least the target disk.
- Use at own risk.

## Install
1. Boot into ubuntu 16.04 live
2. Make sure target disk it not in use (should also be unmounted)
3. Run install.sh with root `sudo curl https://raw.githubusercontent.com/VegarM/auto-luks-zfs/master/install.sh | bash`

## References
Based on https://github.com/zfsonlinux/zfs/wiki/Ubuntu-16.04-Root-on-ZFS
