#!/bin/bash

set -eou pipefail

live="/home/qemu/vm/live/oba"
disk_qemu='hda.img'
iso_qemu='cidata.iso'

# virtual cpus must be an int
vcpus='1'
# memory must be an int, measured in megabytes
memory="$((2 * 1024))"
# virtual machine needs to be assigned a mac address
macaddr='52:54:67:23:02:41'

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
    -net nic,model=virtio,macaddr="${macaddr}" -net bridge,br=br0 \
    -cpu host -enable-kvm -machine type=q35,accel=kvm -smp "${vcpus}" \
    -m "${memory}" \
    -nographic \
    -hda "${live}"/"${disk_qemu}" -cdrom "${live}"/"${iso_qemu}"
#   -hda "${live}"/"${disk_qemu}" -cdrom "${live}"/"${iso_qemu}" \
#   -blockdev node-name=q1,driver=raw,file.driver=host_device,file.filename=/dev/sdb2 \
#   -device virtio-blk,drive=q1
