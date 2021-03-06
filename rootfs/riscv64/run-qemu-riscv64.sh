#!/bin/bash

progdir=$(cd $(dirname "$0"); pwd)
. "${progdir}/../scripts/config.sh"
. "${progdir}/../scripts/common.sh"

parse_args "$@"
shift $((OPTIND - 1))

_fixup="$1"

QEMU=${QEMU:-${QEMU_BIN}/qemu-system-riscv64}
PREFIX=riscv64-linux-
ARCH=riscv
PATH_RISCV=/opt/kernel/riscv64/gcc-7.3.0/bin

PATH=${PATH}:${PATH_RISCV}

patch_defconfig()
{
    : # nothing to do
}

cached_config=""

runkernel()
{
    local mach=$1
    local defconfig=$2
    local fixup=$3
    local rootfs=$4
    local pid
    local waitlist=("Power off" "Boot successful" "Requesting system poweroff")
    local logfile="$(__mktemp)"
    local build="${ARCH}:${mach}:${defconfig}${fixup:+:${fixup}}"

    if [[ "${rootfs%.gz}" == *cpio ]]; then
	build+=":initrd"
    else
	build+=":rootfs"
    fi

    if ! match_params "${_fixup}@${fixup}"; then
	echo "Skipping ${build} ... "
	return 0
    fi

    echo -n "Building ${build} ... "

    if ! checkskip "${build}" ; then
	return 0
    fi

    if ! dosetup -c "${defconfig}" -d -F "${fixup}" "${rootfs}" "${defconfig}"; then
	return 1
    fi

    echo -n "running ..."

    [[ ${dodebug} -ne 0 ]] && set -x

    ${QEMU} -M virt -m 512M -no-reboot \
	-bios "${progdir}/bbl" \
	-kernel vmlinux \
	-netdev user,id=net0 -device virtio-net-device,netdev=net0 \
	${extra_params} \
	-append "${initcli} console=ttyS0,115200" \
	-nographic -monitor none \
	> ${logfile} 2>&1 &
    pid=$!

    [[ ${dodebug} -ne 0 ]] && set +x

    dowait ${pid} ${logfile} automatic waitlist[@]
    return $?
}

echo "Build reference: $(git describe)"
echo

retcode=0
runkernel virt defconfig "" rootfs.cpio.gz
retcode=$((retcode + $?))
runkernel virt defconfig virtio-blk rootfs.ext2.gz
retcode=$((retcode + $?))

exit ${retcode}
