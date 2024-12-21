#!/bin/bash

set -e

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
#qemu-system-x86_64 -net nic -net user -machine accel=kvm:tcg -m 512 -nographic -hda noble-server-cloudimg-amd64.img -cdrom ubuntu-cloud-init.iso

# run with bridged network 
# requires the host to have a bridge called br0
qemu-system-x86_64 -netdev bridge,br=br0,id=net0 -device virtio-net-pci,netdev=net0 \
 -machine accel=kvm:tcg -m 512 -nographic \
 -hda "${live}"/"${disk_qemu}" -cdrom "${live}"/"${iso_qemu}"
