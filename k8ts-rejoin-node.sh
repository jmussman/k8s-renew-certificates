#!/bin/bash
#
# renew-k8s-certs
# Copyright (c) 2024-2025 Joel A Mussman. All rights reserved.
#
# Rejoin a node to the cluster when the node certificate has expired. The automatic renewal
# of node certificates does not take place if the certificate is already expired.
#

function matchNode() {
    readarray -t nodelist <<<"$(kubectl get nodes -o wide --no-headers)"
    for node in "${nodelist[@]}"; do
        if [[ "${nodeelements[0]}" == "$1" && "${nodeelements[2]}" == '<none>' ]]; then
            echo "${nodelements[@]}"
            break;
        fi
    done
}

function rejoinNode() {
    echo "Rejoining node $1 ($2) to the cluster; be prepared with the root password:"
    sedcommand="'s/^.*=\\(.*\)\$/\\1/'"
    checkdate='$(date -d "$(openssl x509 -enddate -noout -in /var/lib/kubelet/kubelet-client-current.pem | sed $sedcommand)" +%s) lt $(date +%s)'
    joinCommand='$(kubeadm token create --print-join-command) --ignore-preflight-errors=all'
    ssh "root@$2" "if [[ $checkdate ]]; then $joincommand; fi"
}

function main() {

    node=$(matchNode)
    if [[ ! -z "$node" ]]; then rejoinNode $node[0] $node[5]; fi
}

main $@