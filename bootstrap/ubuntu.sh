#!/bin/bash

#set -mex
set -e

disk_qemu='hda.img'
iso_qemu='cidata.iso'

while [[ -n "${3}" ]]; do
    case "${1}" in
        --user) 
            default_user="${2}"
            ;;
        --host)
            hostname="${2}"
            ;;
        *)
            echo "Something went wrong when parsing command line arguments..." 1>&2
            echo "${1} is not a flag..." 1>&2
            exit 1
            ;;
    esac
    shift 2
done

: "${default_user:=ubuntu}"
: "${hostname:=ubuntu}"

indent () {
    if [[ -z "${2}" ]]; then
        exit 1
    fi

    files=()
    while [[ -n "${2}" ]]; do
        files+=("${1}")
        shift
    done
    num="${1}"

    spaces="$(for _ in $(seq 1 "${num}"); do printf ' '; done)"
    # shellcheck disable=SC2002 # cat is needed so that I can treat dir/* as if it were one single file
    cat "${files[@]}" | head -n 1
    # shellcheck disable=SC2002 # cat is needed so that I can treat dir/* as if it were one single file
    cat "${files[@]}" | tail -n+2 | sed "s/^/${spaces}/"
}

list () {
    if [[ -z "${2}" ]]; then
        exit 1
    fi

    files=()
    while [[ -n "${2}" ]]; do
        files+=("${1}")
        shift
    done
    num="${1}"

    if [[ "${num}" -lt 2 ]]; then
        exit 2
    fi

    spaces="$(for _ in $(seq 1 "${num}"); do printf ' '; done)"
    # shellcheck disable=SC2002 # cat is needed so that I can treat dir/* as if it were one single file
    cat "${files[@]}" | head -n 1 | sed 's/^/- /'
    # shellcheck disable=SC2002 # cat is needed so that I can treat dir/* as if it were one single file
    cat "${files[@]}" | tail -n+2 | sed 's/^/- /' | sed "s/^/${spaces}/"
}

keyid () {
    if [[ -z "${1}" ]]; then
        exit 1
    fi
    wget -q -O - "${1}" | gpg --show-keys | sed '2q;d' | sed 's/ //g'
}

if [[ -z "${2}" ]] || [[ ! -f "${1}" ]] || [[ -f "${2}" ]]; then
    echo "COMMAND STATIC LIVE" 1>&2
    exit 1
fi

disk_source="${1}"
live="${2}"

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

if [[ ! -f "${live}"/"${disk_qemu}" ]]; then
    cp "${disk_source}" "${live}"/"${disk_qemu}"
fi

if [[ ! -f "${user}"/default_user ]]; then
    echo "${default_user}" > "${user}"/default_user
fi

if [[ ! -f "${user}"/hostname ]]; then
    echo "${hostname}" > "${user}"/hostname
fi

if [[ ! -f "${user}"/password ]]; then
    head /dev/urandom | tr -dc '[:alnum:]' | head -c 20 > "${user}"/password
fi

if [[ ! -f "${host_keys}"/ecdsa ]] && [[ ! -f "${host_keys}"/ecdsa.pub ]]; then
    ssh-keygen -q -t ecdsa -f "${host_keys}"/ecdsa -N "" -C ""
fi

if [[ ! -f "${host_keys}"/ed25519 ]] && [[ ! -f "${host_keys}"/ed25519.pub ]]; then
    ssh-keygen -q -t ed25519 -f "${host_keys}"/ed25519 -N "" -C ""
fi

if [[ ! -f "${host_keys}"/rsa ]] && [[ ! -f "${host_keys}"/rsa.pub ]]; then
    ssh-keygen -q -t rsa -b 3092 -f "${host_keys}"/rsa -N "" -C ""
fi

if [[ ! -f "${authorized_keys}"/ecdsa ]] && [[ ! -f "${authorized_keys}"/ecdsa.pub ]]; then
    ssh-keygen -q -t ecdsa -f "${authorized_keys}"/ecdsa -N "" -C ""
fi

if [[ ! -f "${authorized_keys}"/ed25519 ]] && [[ ! -f "${authorized_keys}"/ed25519.pub ]]; then
    ssh-keygen -q -t ed25519 -f "${authorized_keys}"/ed25519 -N "" -C ""
fi

if [[ ! -f "${authorized_keys}"/rsa ]] && [[ ! -f "${authorized_keys}"/rsa.pub ]]; then
    ssh-keygen -q -t rsa -b 3092 -f "${authorized_keys}"/rsa -N "" -C ""
fi

while IFS= read -r; do
    echo "${REPLY}" >> "${cloud_init}"/user-data
done <<EOF
#cloud-config

system_info:
  default_user:
    name: ${default_user}
hostname: ${hostname}
create_hostname_file: true

password: $(cat "${user}"/password)
chpasswd:
  expire: false

# Using keyid in this way only works if the maintainer of the repository you want to add also makes sure to upload their keys to keyserver.ubuntu.com
apt:
  sources:
    grafana:
      keyid: $(keyid https://apt.grafana.com/gpg.key)
      keyserver: keyserver.ubuntu.com
      source: 'deb [signed-by=\$KEY_FILE] https://apt.grafana.com stable main'

packages:
  - apt: [avahi-daemon, libnss-mdns]

ssh_pwauth: false
allow_public_ssh_keys: true
disable_root: true
disable_root_opts: no-port-forwarding,no-agent-forwarding,no-X11-forwarding
ssh_deletekeys: true
ssh_authorized_keys: 
  $(list "${authorized_keys}"/*.pub 2)
ssh_keys: 
  rsa_private: |
    $(indent "${host_keys}"/rsa 4)
  rsa_public: $(cat "${host_keys}"/rsa.pub)
  ed25519_private: |
    $(indent "${host_keys}"/ed25519 4)
  ed25519_public: $(cat "${host_keys}"/ed25519.pub)
  ecdsa_private: |
    $(indent "${host_keys}"/ecdsa 4)
  ecdsa_public: $(cat "${host_keys}"/ecdsa.pub)
EOF

while IFS= read -r; do
    echo "${REPLY}" >> "${cloud_init}"/meta-data
done <<EOF
instance-id: private/arch
EOF

touch "${cloud_init}"/vendor-data

if [[ ! -f "${live}"/"${iso_qemu}" ]]; then
    xorriso -as genisoimage -output "${live}"/"${iso_qemu}" -volid CIDATA -joliet -rock "${cloud_init}"
fi

while IFS= read -r; do
    echo "${REPLY}"
done <<EOF
Add to ssh config:
HOST $(cat "${user}"/hostname).*
    ...
    IdentitiesOnly yes
    IdentityFile $(readlink -f "${authorized_keys}/ecdsa")
    IdentityFile $(readlink -f "${authorized_keys}/ed25519")
    IdentityFile $(readlink -f "${authorized_keys}/rsa")
EOF
