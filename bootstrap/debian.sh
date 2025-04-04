#!/bin/bash

#set -mex
set -e

disk_qemu='hda.img'
iso_qemu='cidata.iso'
root_ca_file='/home/dv/workspace/homelab/certs/root_2125.crt'

# for the files supplied as arguments indent everything except the first 
# line of the first file ${1} spaces
indent () {
    if [[ -z "${2}" ]]; then
        exit 1
    fi

    export whitespace="${1}"
    shift
    perl -pe '$a = " " x $ENV{whitespace}; s/^/$a/ if 2 .. END' "${@}"
    unset whitespace
}

# for the files supplied as arguments indent everything except the first 
# line of the first file ${1} spaces and format as a yaml list
list () {
    if [[ -z "${2}" ]]; then
        exit 1
    fi

    export whitespace="${1}"
    shift
    perl -pe '$a = " " x $ENV{whitespace} . "- "; s/^/$a/ if 2 .. END' "${@}"
    unset whitespace
}

# cloud-init has poor support for working with gpg keys. Bootstrap from
# cloud-init to ansible and run ansible scripts.
#keyid () {
#    if [[ -z "${1}" ]]; then
#        exit 1
#    fi
#    wget -q -O - "${1}" | gpg --show-keys --with-fingerprint | sed '2q;d' | sed 's/ //g'
#}

# use my favorite templating language: BASH
while [[ -n "${3}" ]]; do
    case "${1}" in
        --user) 
            default_user="${2}"
            ;;
        --host)
            hostname="${2}"
            ;;
        --pass)
            password="${2}"
            ;;
        *)
            echo "Something went wrong when parsing command line arguments..." 1>&2
            echo "${1} is not a flag..." 1>&2
            exit 1
            ;;
    esac
    shift 2
done

# sanity check
if [[ -z "${2}" ]] || [[ ! -f "${1}" ]] || [[ -f "${2}" ]]; then
    echo "bootstrap.sh requires \$1=/path/to/backing-image.qcow2 \$2=/path/to/output-directory/" 1>&2
    exit 1
fi

: "${default_user:=debian}"
: "${hostname:=debian}"

disk_source="${1}"
live="${2}"

if [[ -f "${live}" ]] || [[ -d "${live}" ]]; then
    echo "Hey delete ${live} yourself, I don't want to clobber it myself" 1>&2
    exit 1
fi

secrets="${live}"/secrets
user="${secrets}"/user
host_keys="${secrets}"/host_keys
authorized_keys="${secrets}"/authorized_keys

cloud_init="${live}"/cloud-init

mkdir -p "${live}"
mkdir -p "${secrets}"
mkdir -p "${user}"
mkdir -p "${host_keys}"
mkdir -p "${authorized_keys}"
mkdir -p "${cloud_init}"

qemu-img create -f qcow2 -F qcow2 -o backing_file="$(readlink -f "${disk_source}")" "${live}"/"${disk_qemu}"
echo "${default_user}" > "${user}"/default_user
echo "${hostname}" > "${user}"/hostname
openssl rand 20 | base64 > "${user}"/password
: "${password:=$(cat "${user}"/password)}"
ssh-keygen -q -t ed25519 -f "${host_keys}"/ed25519 -N "" -C "root@${hostname}"
ssh-keygen -q -t ed25519 -f "${authorized_keys}"/ed25519 -N "" -C "${default_user}@${hostname}"

cat > "${cloud_init}"/user-data <<EOF
#cloud-config

system_info:
  default_user:
    name: ${default_user}
hostname: ${hostname}
create_hostname_file: true

password: ${password}
chpasswd:
  expire: false

ssh_pwauth: false
allow_public_ssh_keys: true
disable_root: true
disable_root_opts: no-port-forwarding,no-agent-forwarding,no-X11-forwarding
ssh_deletekeys: true
ssh_genkeytypes:
  - ed25519

# DHCP virtual machine + Static SSH Keys

packages:
  - avahi-daemon
  - libnss-mdns

ssh_authorized_keys: 
  - $(list 2 "${authorized_keys}"/*.pub)
ssh_keys: 
  ed25519_private: |
    $(indent 4 "${host_keys}"/ed25519)
  ed25519_public: $(cat "${host_keys}"/ed25519.pub)

# Static IP virtual machine

#ntp:
#  enabled: true
#  ntp_client: systemd-timesyncd
#  servers: 
#  - ntp.home.arpa

#ca_certs:
#  remove_defaults: false # please make sure remove_defaults is disabled
#  trusted:
#  - |
#    $(indent 4 ${root_ca_file})
#

#write_files:
#  - content: "trust this ssh cert you get from vault dude"
#    path: /etc/ssh/ssh_known_hosts
#    owner: root:root
#    permissions: '0644'
#    append: true
EOF

cat > "${cloud_init}"/network-config <<EOF
#network-config
version: 2
ethernets:
  enp0s2:
    dhcp4: true
EOF

cat > "${cloud_init}"/meta-data <<EOF
instance-id: private/arch
EOF

touch "${cloud_init}"/vendor-data

if [[ ! -f "${live}"/"${iso_qemu}" ]]; then
    xorriso -as genisoimage -output "${live}"/"${iso_qemu}" -volid CIDATA -joliet -rock "${cloud_init}"
fi

cat <<EOF
Add to ssh config:
HOST $(cat "${user}"/hostname).*
    IdentitiesOnly yes
    IdentityFile $(readlink -f "${authorized_keys}/ed25519")
EOF
