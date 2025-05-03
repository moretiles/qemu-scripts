#!/bin/bash

#set -mex
set -euo pipefail

unset peer

umask 077

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
while (( ${#} >= 6 )); do
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
if (( ${#} != 5 )); then
    echo "azure_bootstrap.sh requires \$1=output_directory \$2=internal_wireguard_address \$3=internal_wireguard_endpoint \$4=internal_wireguard_public_key \$5=internal_wireguard_subnet" 1>&2 #gitleaks:allow
    echo "As an example:" 1>&2
    echo "               ./azure_bootstrap.sh ubuntu 172.29.4.3/24 172.19.4.1 asdsad...= 172.19.4.0/24" #gitleaks:allow
    exit 1
fi

: "${default_user:=debian}"
: "${hostname:=debian}"

live="${1}"
internal_wireguard_address="${2}"
internal_wireguard_endpoint="${3}"
internal_wireguard_endpoint_pub="${4}"
internal_wireguard_network="${5}"

if [[ -f "${live}" ]] || [[ -d "${live}" ]]; then
    echo "Hey delete ${live} yourself, I don't want to clobber it myself" 1>&2
    exit 1
fi

secrets="${live}"/secrets
user="${secrets}"/user
host_keys="${secrets}"/host_keys
authorized_keys="${secrets}"/authorized_keys
wireguard_keys="${secrets}"/wireguard_keys

cloud_init="${live}"/cloud-init

mkdir -p "${live}"
mkdir -p "${secrets}"
mkdir -p "${user}"
mkdir -p "${host_keys}"
mkdir -p "${authorized_keys}"
mkdir -p "${wireguard_keys}"
mkdir -p "${cloud_init}"

echo "${default_user}" > "${user}"/default_user
echo "${hostname}" > "${user}"/hostname
openssl rand 20 | base64 > "${user}"/password
: "${password:=$(cat "${user}"/password)}"
ssh-keygen -q -t ed25519 -f "${host_keys}"/ed25519 -N "" -C "root@${hostname}"
ssh-keygen -q -t ed25519 -f "${authorized_keys}"/ed25519 -N "" -C "${default_user}@${hostname}"
wg genkey > "${wireguard_keys}"/internal_priv
wg pubkey < "${wireguard_keys}"/internal_priv > "${wireguard_keys}"/internal_pub

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
ssh_deletekeys: false
ssh_genkeytypes:
  - ed25519

ssh_authorized_keys: 
  - $(list 2 "${authorized_keys}"/*.pub)
ssh_keys: 
  ed25519_private: |
    $(indent 4 "${host_keys}"/ed25519)
  ed25519_public: $(cat "${host_keys}"/ed25519.pub)

packages:
  - wireguard
  - wireguard-tools

ca_certs:
  remove_defaults: false # please make sure remove_defaults is disabled
  trusted:
    - |
      $(indent 4 ${root_ca_file})

wireguard:
  interfaces:
    - name: wg0
      config_path: /etc/wireguard/wg0.conf
      content: |
        [Interface]
        Privatekey = $(cat "${wireguard_keys}"/internal_priv)
        Address = ${internal_wireguard_address}
        [Peer]
        PublicKey = ${internal_wireguard_endpoint_pub}
        AllowedIps = ${internal_wireguard_network}
        Endpoint = ${internal_wireguard_endpoint}
  readinessprobe:
    - 'systemctl enable --now wg-quick@wg0.service'
EOF

cat <<EOF
This script is right now very untested and unfinished.

Add to ssh config:
HOST $(cat "${user}"/hostname).*
    IdentitiesOnly yes
    IdentityFile $(readlink -f "${authorized_keys}/ed25519")
EOF
