#!/bin/bash

set -mex

INTERFACE="$(ip --br addr | grep 'enp\|eth' | awk '{print $1}' | head -n 1)"
BRIDGE=br0

if [[ "$(id -u)" -ne 0 ]]; then
    echo "Need to run as root" 1>&2
    exit 1
fi

ip link set "${INTERFACE}" nomaster
ip link delete "${BRIDGE}" type bridge
