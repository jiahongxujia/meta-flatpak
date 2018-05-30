#!/bin/sh

PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/lib/ostree:/usr/lib64/ostree

ROOT_MOUNT="/sysroot"
MOUNT="/bin/mount"
UMOUNT="/bin/umount"
ROOT_DELAY="0"
OSTREE_SYSROOT=""
#OSTREE_LABEL_ROOT="otaroot"
OSTREE_LABEL_BOOT="otaboot"
OSTREE_LABEL_FLUXDATA="fluxdata"
# The timeout (tenth of a second) for rootfs on low speed device
MAX_TIMEOUT_FOR_WAITING_LOWSPEED_DEVICE=60

# Copied from initramfs-framework. The core of this script probably should be
# turned into initramfs-framework modules to reduce duplication.
udev_daemon() {
	OPTIONS="/sbin/udev/udevd /sbin/udevd /lib/udev/udevd /lib/systemd/systemd-udevd"

	for o in $OPTIONS; do
		if [ -x "$o" ]; then
			echo $o
			return 0
		fi
	done

	return 1
}

_UDEV_DAEMON=`udev_daemon`

do_mount_fs() {
	echo "mounting FS: $*"
	[[ -e /proc/filesystems ]] && { grep -q "$1" /proc/filesystems || { log_error "Unknown filesystem"; return 1; } }
	[[ -d "$2" ]] || mkdir -p "$2"
	[[ -e /proc/mounts ]] && { grep -q -e "^$1 $2 $1" /proc/mounts && { log_info "$2 ($1) already mounted"; return 0; } }
	mount -t "$1" "$1" "$2"
}

early_setup() {

    do_mount_fs proc /proc
    do_mount_fs sysfs /sys
    mount -t devtmpfs none /dev
    do_mount_fs devpts /dev/pts
    do_mount_fs tmpfs /dev/shm
    do_mount_fs tmpfs /tmp
    do_mount_fs tmpfs /run

    $_UDEV_DAEMON --daemon
    udevadm trigger --action=add

    if [ -x /sbin/mdadm ]; then
	/sbin/mdadm -v --assemble --scan --auto=md
    fi
}

read_args() {
    [ -z "$CMDLINE" ] && CMDLINE=`cat /proc/cmdline`
    for arg in $CMDLINE; do
        optarg=`expr "x$arg" : 'x[^=]*=\(.*\)'`
        case $arg in
            ostree_root=*)
		OSTREE_ROOT_DEVICE=$optarg ;;
            root=*)
                ROOT_DEVICE=$optarg ;;
            rootdelay=*)
                ROOT_DELAY=$optarg ;;
            rootflags=*)
		ROOT_FLAGS=$optarg ;;
            init=*)
                INIT=$optarg ;;
        esac
    done
}

expand_fluxdata() {

   fluxdata_label=$1
   [ -z $fluxdata_label ] && echo "No fluxdata partition found." && return 0

   # expanding FLUXDATA
   datapart=$(blkid -s LABEL | grep "LABEL=\"$fluxdata_label\"" |head -n 1| awk -F: '{print $1}')

   # no fluxdata or fluxdata is a LUKS(expanding done at LUKS creation)
   [ -z ${datapart} ] && return 0

   datadev=$(lsblk $datapart -n -o PKNAME | head -n 1)
   datadevnum=$(echo ${datapart} | sed 's/\(.*\)\(.\)$/\2/')

   echo "Expanding partition for ${fluxdata_label} datadev: ${datadev}, datadevnum: ${datadevnum}"
   parted -s /dev/$datadev -- resizepart $datadevnum -1
			     
   echo "Expanding FS for ${fluxdata_label}"
   resize2fs -f ${datapart}
}

fatal() {
    echo $1 >$CONSOLE
    echo >$CONSOLE
    exec sh
}

#######################################

early_setup

read_args

[ -z "$CONSOLE" ] && CONSOLE="/dev/console"
[ -z "$INIT" ] && INIT="/sbin/init"


udevadm settle --timeout=3 --quiet
killall "${_UDEV_DAEMON##*/}" 2>/dev/null

mkdir -p $ROOT_MOUNT/

sleep ${ROOT_DELAY}

[ -z $OSTREE_ROOT_DEVICE ] && fatal "No OSTREE root device specified, please add 'ostree_root=LABEL=xyz' in bootline!" || {
    echo "Waiting for low speed devices to be available ..."
    ostree_root_label=$(echo $OSTREE_ROOT_DEVICE | cut -f 2 -d'=')
    retry=0
    # For LUKS, we might wait for MAX_TIMEOUT_FOR_WAITING_LOWSPEED_DEVICE/10s
    while [ $retry -lt $MAX_TIMEOUT_FOR_WAITING_LOWSPEED_DEVICE ] ; do
	retry=$(($retry+1))
        blkid -t LABEL=$ostree_root_label && break
        blkid -t LABEL=luks_$ostree_root_label && break
	#echo "sleep to wait for $OSTREE_ROOT_DEVICE"
        sleep 0.1
    done
}
try_to_mount_rootfs() {
    local mount_flags="rw,noatime,iversion"
    mount_flags="${mount_flags},${ROOT_FLAGS}"
    
    mount -o $mount_flags "${OSTREE_ROOT_DEVICE}" "${ROOT_MOUNT}" 2>/dev/null && return 0
}

[ -x /init.luks ] && {
    expand_fluxdata luks_$OSTREE_LABEL_FLUXDATA
    /init.luks /sysroot_luks && {
        echo "LUKS init done."
    } || fatal "Couldn't init LUKS, dropping to shell"
} || expand_fluxdata $OSTREE_LABEL_FLUXDATA

echo "Waiting for root device to be ready..."
while [ 1 ] ; do
    try_to_mount_rootfs && break
    sleep 0.1
done

echo "Waiting for boot device to be ready..."
while [ 1 ] ; do
    mount "LABEL=otaboot" "${ROOT_MOUNT}/boot" && break
    sleep 0.1
done

ostree-prepare-root ${ROOT_MOUNT}

# Move the mount points of some filesystems over to
# the corresponding directories under the real root filesystem.
for dir in `cat /proc/mounts | grep -v rootfs | awk '{print $2}'` ; do
    mkdir -p  ${ROOT_MOUNT}/${dir##*/}
    mount -nv --move $dir ${ROOT_MOUNT}/${dir##*/}
done

cd $ROOT_MOUNT

# If we pass args to bash, it will assume they are text files
# to source and run.
if [ "$INIT" == "/bin/bash" ] || [ "$INIT" == "/bin/sh" ]; then
    CMDLINE=""
fi

# !!! The Big Fat Warnings !!!
#
# The IMA policy may enforce appraising the executable and verifying the
# signature stored in xattr. However, ramfs doesn't support xattr, and all
# other initializations must *NOT* be placed after IMA initialization!
[ -x /init.ima ] && /init.ima $ROOT_MOUNT && {
    # switch_root is an exception. We call it in the real rootfs and it
    # should be already signed properly.
    switch_root="usr/sbin/switch_root.static"
} || {
    switch_root="switch_root"
}

exec $switch_root $ROOT_MOUNT $INIT $CMDLINE ||
    fatal "Couldn't switch_root, dropping to shell"
