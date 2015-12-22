#!/bin/bash

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
rundir=$PWD


###############################################################################
### Utilities                                                               ###
###############################################################################

#
# Generate a random file path in the workdir directory
#
tempfile() {
    echo "${workdir}/tmp_$(date +%Y%m%d%H%M%S)_${RANDOM}"
}

#
# Read a value in the JSON configuration file
#
# $1 - key in the json file
#
config() {
    cat ${config_file} | jq -r ".${1}"
}

#
# Exec a command in the chroot context
#
# $@ - command to execute
#
chroot_exec() {
    LANG=C chroot ${rootfs} $@
}

#
# Get the absolute file path from the relative one.
#
# $1 - Relative or even absolute filepath
#
get_absolute_path() {
    if [ ! -e $1 ] ; then
        exit_on_error "$1 does not exist"
    fi
    readlink -f $1
}


###############################################################################
### Handle input CLI configuration                                          ###
###############################################################################

config_file=
trace=false

print_usage() {
    echo "Usage: rpi-debian-builder [options] --config config.json"
    echo ""
    echo "Options:"
    echo ""
    echo "  -t --trace     Output debug traces on stderr"
    echo "  -h --help      Print this help"
    echo ""
}

#
# $1 - Error message to display
#
exit_on_error() {
    echo "Error... $1"
    exit 1
}

#
# $1 - flag name
# $2 - flag value
#
check_cli_arg() {
    if [ -z "$2" ] ; then
        exit_on_error "Error... parameter $1 needs an argument"
    fi
}

#
# $1 - Variable name
# $2 - Error message if missing
#
check_mandatory() {
    if [ -z ${!1} ] ; then
        exit_on_error "$2"
    fi
}

while [ $# -ne 0 ] ; do
    case $1 in
        -c | --config)
            check_cli_arg $1 $2 ; shift ; config_file=$1 ;;

        -t | --trace)
            trace=true ;;

        -h | --help)
            print_usage && exit 0 ;;

        *)
            echo "Error... Unknown option $1"
            echo ""
            print_usage
            exit 1
    esac
    shift
done

check_mandatory config_file "--config flag is missing"
config_file=$(get_absolute_path ${config_file})

if [ "${trace}" == "true" ] ; then
    set -x
fi


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

kpartx -v -d ${image}

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
