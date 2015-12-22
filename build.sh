#!/bin/bash

set -ex

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

rundir=$PWD

tempfile() {
    echo "${workdir}/tmp_$(date +%Y%m%d%H%M%S)_${RANDOM}"
}

config() {
    cat ${SCRIPT_DIR}/config.json | jq -r ".${1}"
}

chroot_exec() {
    LANG=C chroot ${rootfs} $@
}


###############################################################################
### Prepare temporary working directory                                     ###
###############################################################################

workdir=/tmp/build
rootfs="${workdir}/root"
bootfs="${rootfs}/boot"
rm -rf ${workdir}
mkdir -p ${workdir}


###############################################################################
### Create a virtual block device                                           ###
###############################################################################

block_size=$(config partitions.block_size)
disk_size=$(config partitions.disk_size)
boot_size=$(config partitions.boot_size)

image=${workdir}/rpi.img

dd if=/dev/zero of=${image} bs=${block_size} count=$((${disk_size}/${block_size}))


###############################################################################
### Create 'boot' and 'root' partitions                                     ###
###############################################################################

device=$(losetup --find --show ${image})

set +e

fdisk ${device} << EOF
n
p
1

+$((${boot_size} / 1024))K
t
c
n
p
2


w
EOF

set -e

losetup -d ${device}


###############################################################################
### Create a loop device for 'boot' and 'root' partitions                   ###
###############################################################################

p=( $(kpartx -v -a ${image} | awk '{print $3}') )

declare -A partition

partition[boot]=/dev/mapper/${p[0]}
partition[root]=/dev/mapper/${p[1]}

unset p

sleep 5


###############################################################################
### Create filesystems for 'boot' and 'root' partitions                     ###
###############################################################################

mkfs.vfat ${partition[boot]}
mkfs.ext4 ${partition[root]}


###############################################################################
### Mount 'root' partition                                                  ###
###############################################################################

mkdir -p ${rootfs}
mount ${partition[root]} ${rootfs}


###############################################################################
### Prepare chroot                                                          ###
###############################################################################

mkdir -p ${rootfs}/proc
mkdir -p ${rootfs}/sys
mkdir -p ${rootfs}/dev
mkdir -p ${rootfs}/dev/pts

mount -t proc none ${rootfs}/proc
mount -t sysfs none ${rootfs}/sys
mount -o bind /dev ${rootfs}/dev
mount -o bind /dev/pts ${rootfs}/dev/pts


###############################################################################
### Debootstrap first stage                                                 ###
###############################################################################

deb_release=$(config "debian.release")
deb_mirror=$(config "debian.mirror")
deb_local_mirror=$(config "debian.mirror_local")

debootstrap --foreign --arch armhf ${deb_release} ${rootfs} ${deb_local_mirror}


###############################################################################
### Debootstrap second stage using qemu                                     ###
###############################################################################

cp /usr/bin/qemu-arm-static ${rootfs}/usr/bin/
LANG=C chroot ${rootfs} /debootstrap/debootstrap --second-stage


###############################################################################
### Mount boot partition on /boot                                           ###
###############################################################################

mount ${partition[boot]} ${bootfs}


###############################################################################
### Write some configuration files                                          ###
###############################################################################

cat > ${rootfs}/boot/cmdline.txt <<EOF
dwc_otg.lpm_enable=0 console=ttyAMA0,115200 kgdboc=ttyAMA0,115200 console=tty1 root=/dev/mmcblk0p2 rootfstype=ext4 rootwait
EOF

cat > ${rootfs}/etc/apt/sources.list <<EOF
deb ${deb_local_mirror} ${deb_release} main contrib non-free
EOF

cat > ${rootfs}/etc/fstab <<EOF
proc            /proc           proc    defaults        0       0
/dev/mmcblk0p1  /boot           vfat    defaults        0       0
EOF

echo $(config "debian.hostname") > ${rootfs}/etc/hostname

cat > ${rootfs}/etc/network/interfaces <<EOF
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp
EOF


###############################################################################
### Set root password                                                       ###
###############################################################################

root_password=$(config "debian.root_password")
chroot_exec chpasswd <<EOF
root:${root_password}
EOF

chroot_exec apt-get update


###############################################################################
### Install RaspberryPi firmware                                            ###
###############################################################################

chroot_exec bash <<EOF
set -ex
apt-get -y install git-core binutils ca-certificates curl
curl -L https://raw.githubusercontent.com/Hexxeh/rpi-update/master/rpi-update > /usr/bin/rpi-update
chmod +x /usr/bin/rpi-update
SKIP_BACKUP=1 rpi-update
EOF


###############################################################################
### Install packages                                                        ###
###############################################################################

while read package ; do
    chroot_exec apt-get -y install ${package}
done < <(config "debian.packages[]")


###############################################################################
### Restore real online apt mirror                                          ###
###############################################################################

cat > ${rootfs}/etc/apt/sources.list <<EOF
deb ${deb_mirror} ${deb_release} main contrib non-free
EOF


###############################################################################
### Cleaning                                                                ###
###############################################################################

chroot_exec apt-get clean


###############################################################################
### Umount filesystems and free device mapper and loop device               ###
###############################################################################

sync

sleep 5

umount -l ${bootfs}

sleep 5

set +e
umount -l ${rootfs}/dev/pts
umount -l ${rootfs}/dev
umount -l ${rootfs}/sys
umount -l ${rootfs}/proc
set -e

umount -l ${rootfs}

sleep 5

kpartx -d ${image}

sleep 5


###############################################################################
### Move image in the desired output file                                   ###
###############################################################################

dest=${rundir}/$(config "output.image_name")
mv ${image} ${dest}

set +x

echo ""
echo "### Image successfully created in ${dest} ###"
echo ""
