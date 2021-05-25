#!/bin/bash

# Utility for setting up kubeseal
# Version: 1.0
# Author: Paul Carlton (mailto:paul.carlton@weave.works)

set -euo pipefail

function usage()
{
    echo "usage ${0} [--debug] [--privatekey-file <privatekey-file>] [--pubkey-file <pubkey-file>]"
    echo "<privatekey-file> is the path of private key file, defaults to $HOME/sealed-secrets-key"
    echo "<pubkey-file> is the path to store the public key file, defaults to $HOME/pub-sealed-secrets.pem"
    echo "This script will setup kubeseal on a cluster"
}

function args() {
  privatekey_file="$HOME/sealed-secrets-key"
  pubkey_file="$HOME/pub-sealed-secrets.pem"
  debug=""
  arg_list=( "$@" )
  arg_count=${#arg_list[@]}
  arg_index=0
  while (( arg_index < arg_count )); do
    case "${arg_list[${arg_index}]}" in
          "--pubkey-file") (( arg_index+=1 ));pubkey_file="${arg_list[${arg_index}]}";;
          "--privatekey-file") (( arg_index+=1 ));privatekey_file="${arg_list[${arg_index}]}";;
          "--debug") set -x; debug="--debug";;
               "-h") usage; exit;;
           "--help") usage; exit;;
               "-?") usage; exit;;
        *) if [ "${arg_list[${arg_index}]:0:2}" == "--" ];then
               echo "invalid argument: ${arg_list[${arg_index}]}"
               usage; exit
           fi;
           break;;
    esac
    (( arg_index+=1 ))
  done
}

args "$@"

private_key=$(echo -n ${privatekey_file} | base64 --wrap=0)
public_key=$(echo -n ${pubkey_file} | base64 --wrap=0)

kubectl apply -f - << EOF
apiVersion: v1
data:
  tls.crt: ${public_key} 
  tls.key: ${private_key}
kind: Secret
metadata:
  labels:
    sealedsecrets.bitnami.com/sealed-secrets-key: active
  name: sealed-secrets-key
  namespace: kube-system
type: kubernetes.io/tls
EOF

flux create source helm sealed-secrets \
--interval=1h \
--url=https://bitnami-labs.github.io/sealed-secrets

flux create helmrelease sealed-secrets \
--interval=1h \
--release-name=sealed-secrets \
--target-namespace=kube-system \
--source=HelmRepository/sealed-secrets \
--chart=sealed-secrets \
--chart-version="1.13.x"

if [ ! -f "${pubkey_file}" ] ; then
  kubeseal --fetch-cert \
  --controller-name=sealed-secrets \
  --controller-namespace=kube-system \
  > ${pubkey_file}
fi
