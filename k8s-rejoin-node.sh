#!/bin/bash
#
# k8s-rejoin-node
# Copyright (c) 2024-2025 Joel A Mussman. All rights reserved.
#
# Rejoin a node to the cluster when the node certificate has expired. The automatic renewal
# of node certificates does not take place if the certificate is already expired.
#

kubelet_cert_path=/var/lib/kubelet/pki/kubelet-client-current.pem

function match_node() {
    readarray -t node_list <<< "$(kubectl get nodes -o wide --no-headers)"
    for node in "${node_list[@]}"; do
        IFS=' ' read -r -a node_elements <<< "$node"
        if [[ "$node_elements" == "$1" && "${node_elements[2]}" == '<none>' ]]; then
            echo ${node_elements[@]}
            break;
        fi
    done
}

function rejoin_node() {
    echo "Rejoining node $1 ($2) to the cluster; be prepared with the root password:"
    cmd="if [[ \$(date -d \"\$(openssl x509 -enddate -noout -in $kubelet_cert_path "
    cmd+="| cut -d = -f 2)\" +%s) -lt $(date +%s) ]]; then "
    cmd+="$(kubeadm token create --print-join-command) --ignore-preflight-errors=all; fi"
    ssh root@$2 "$cmd"
}

function main() {
    node=$(match_node $1)
    if [[ ! -z "$node" ]]; then 
        IFS=' ' read -r -a node_elements <<< "$node"
        rejoin_node $node_elements ${node_elements[5]}
    fi
}

main $@