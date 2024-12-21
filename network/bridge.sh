#!/bin/bash

set -mex

if [[ "$(id -u)" -ne 0 ]]; then
    echo "Need to run as root" 1>&2
    exit 1
fi

# Note: it is important that host ip includes the mask while gateway includes no mask

INTERFACE="$(ip --br addr | grep 'enp\|eth' | awk '{print $1}' | head -n 1)"
BRIDGE=br0
HOSTIP="$(ip --br addr | grep 'enp\|eth' | awk '{print $3}' | head -n 1)"
GATEWAY="$(ip route | grep 'default' | awk '{print $3}' | sort | uniq)"

#echo interface
#echo "${INTERFACE}"
#echo bridge
#echo "${BRIDGE}"
#echo host
#echo "${HOSTIP}"
#echo gate
#echo "${GATEWAY}"
#exit 0

ip link add name "${BRIDGE}" type bridge
ip address add "${HOSTIP}" dev "${BRIDGE}"
ip link set dev "${BRIDGE}" up
ip link set "${INTERFACE}" master "${BRIDGE}"
ip route append default via "${GATEWAY}" dev "${BRIDGE}"
