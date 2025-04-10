#!/bin/bash

set -e

increment () {
    dir="${HOME}"/.cache/qemu_user_scripts/
    file="${dir}"/mac_offset
    num=0

    mkdir -p "${dir}"
    if [[ -f "${file}" ]]; then
        num="$(cat "${file}")"
    fi
    printf "%x" "${num}"
    num=$(((num + 1) % 256))
    echo "${num}" > "${file}"
}

if [[ -z "${1}" ]]; then
    exit 1
fi

live="${1}"
disk_qemu='hda.img'
iso_qemu='cidata.iso'

if [[ ! -f "${live}"/"${disk_qemu}" ]] || [[ ! -f "${live}"/"${iso_qemu}" ]]; then
    exit 2
fi

# run with host network
#
#qemu-system-x86_64 -net nic -net user -machine accel=kvm:tcg -m 512 -nographic -hda noble-server-cloudimg-amd64.img -cdrom ubuntu-cloud-init.iso

# run with bridged network 
# requires the host to have a bridge called br0
#
qemu-system-x86_64 \
    -net nic,model=virtio,macaddr=52:54:00:00:00:"$(increment)" -net bridge,br=br0 \
    -cpu host -enable-kvm -machine type=q35,accel=kvm -smp 1 \
    -m $((512 * 3)) \
    -nographic \
    -hda "${live}"/"${disk_qemu}" -cdrom "${live}"/"${iso_qemu}" 
#   -hda "${live}"/"${disk_qemu}" -cdrom "${live}"/"${iso_qemu}" \
#   -blockdev node-name=q1,driver=raw,file.driver=host_device,file.filename=/dev/sdb2 \
#   -device virtio-blk,drive=q1
