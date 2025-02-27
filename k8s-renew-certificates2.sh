#!/bin/bash
#
# renew-k8s-certs
# Copyright (c) 2024-2025 Joel A Mussman. All rights reserved.
#

admin_conf=/etc/kubernetes/admin.conf
containers=('kube-apiserver' 'kube-scheduler' 'kube-controller-manager' 'etcd')
cri_endpoint=unix:///run/containerd/containerd.sock
docker_shim_endpoint=unix:///var/run/dockershim.sock
kubelet_pki_path=/var/lib/kubelet/pki
kubelet_cert_path=$kublet_pki_path/kubelet-client-current.pem
kubernetes_cert_path=/etc/kubernetes/pki/apiserver-kubelet-client.crt
kubernetes_key_path=/etc/kubernetes/pki/apiserver-kubelet-client.key
major_cutoff=1
minor_cutoff=23
option='--container-runtime-endpoint'

function show_node_status() {
    kubectl get nodes
}

function wait_for_restart() {
    echo "Restarting system containers; there may be a delay and socket errors as retries happen waiting for the restart to complete:"
    while [[ true ]]; do   
        if [[ -z $(echo $(kubectl get pods --all-namespaces 2>&1) | grep "The connection to the server") ]]; then
            break
        fi
        echo "Waiting another 15 seconds for API restart..."
        sleep 15
    done
}

function stop_system_containers() {
    cre=$1; shift
    for container in "$@"; do
        sudo crictl --runtime-endpoint $cre stop ${container#*:} > /dev/null
    done
}

function retrieve_system_container_ids() {
    container_ids=()
    for container in "${containers[@]}"; do
        container_ids=(${container_ids[@]} "$container:$(sudo crictl --runtime-endpoint $1 ps | grep $container | awk '{print $1}')") 
    done
    echo ${container_ids[@]}
}

function restart_kubernetes_system {
    IFS=' ' read -r -a container_ids <<< $(retrieve_container_ids) $1
    stop_system_containers $1 ${container_ids[@]}
    wait_for_restart
}

function refresh_user_credentials() {
    sudo cp $admin_conf ~/.kube/config
    sudo chown $(id -u):$(id -g) ~/.kube/config
}

function renew_certificates() {
    sudo kubeadm certs renew all
    sudo kubeadm certs check-expiration
}

function kubelet_endpoint_by_version() {
    kv=$(kubeadm version)
    major=$(echo $kv | sed -e 's/^.*Major:"\([[:digit:]]*\).*$/\1/g')
    minor=$(echo $kv | sed -e 's/^.*Minor:"\([[:digit:]]*\).*$/\1/g')
    if (( $major > $majorCutoff || ($major == $majorCutoff && $minor > $minorCutoff ))); then
        echo $criEndpoint
    else
        echo $docker_shim_endpoint
    fi
}

function kubelet_endpoint_by_command() {
    pgrep kubelet > /dev/null && ps --no-headers -fp $(pgrep kubelet) | grep "$option" | sed -e "s/^.*${option}=\([^ ]*\).*$/\1/g"
}

function find_runtime_endpoint() {
    endpoint=$(kubelet_endpoint_by_command)
    if [[ -z $endpoint ]]; then
        endpoint=$(kubelet_endpoint_by_version)
    fi
    echo $endpoint
}

function renew_unexpired_certificate() {
    cre=$(find_runtime_endpoint)
    renew_certificates
    refresh_user_credentials
    restart_kubernetes_system $cre
    show_node_status
}

function rejoin_node() {
    echo "Rejoining node $1 ($2) to the cluster; be prepared with the root password:"
    cmd="if [[ \$(date -d \"\$(openssl x509 -enddate -noout -in $kubelet_cert_pem "
    cmd+="| cut -d = -f 2)\" +%s) -lt $(date +%s) ]]; then "
    cmd+="$(kubeadm token create --print-join-command) --ignore-preflight-errors=all; fi"
    ssh root@$2 "$cmd"
}

function match_worker_nodes() {
    readarray -t node_list <<< "$(kubectl get nodes -o wide --no-headers)"
    for node in "${node_list[@]}"; do
        IFS=' ' read -r -a node_elements <<< "$node"
        if [[ "$node_elements" == "$1" && "${node_elements[2]}" == '<none>' ]]; then
            echo ${node_elements[@]}
        fi
    done
}

function rejoin_worker_nodes() {
    nodes=$(match__worker_nodes $1)
    if [[ ! -z "$node" ]]; then 
        readarray -t node_list <<< "${nodes[@]}"
        for node in ${node_list[@]}; do
            IFS=' ' read -r -a node_elements <<< "$node"
            rejoin_node $node_elements ${node_elements[5]}
        done
    fi
}

function restart_services() {
    sudo systemctl restart kubelet
}

function set_new_certificate() {
    new_certificate_path="$kubelet_pki_path/kubelet-client-$(date +%Y-%m-%d-%H-%M-%S).pem"
    sudo cat $kubernetes_cert_path $kubernetes_key_path > $new_cert_path
    sudo rm -f $kublet_cert_path
    sudo ln -s $new_cert_path $kubelet_cert_path
}

function renew_certificate() {
    sudo kubeadm certs renew all
}

function check_certificate_expiration() {
    if [[ $(sudo openssl x509 -enddate -noout -in $kubeletCertificateFile | cut -c10- | date +%s -f -) -gt $(date +%s) ]]; then
        echo "The kubelet client certificate has not expired, this is not a problem this script can fix!"
    fi
}

function renew_expired_certificate() {
    msg=$(check_certificate_expiration)
    if [[ ! -z "$msg" ]]; then
        echo $msg
    else
        renew_certificate
        set_new_certificate
        restart_services
        refresh_user_credentials
        rejoin_worker_nodes
    fi
}

function check_installation() {
    if [[ -z $(which crictl) || -z $(which kubeadm) || -z $(which kubectl) ]]; then
    	echo "Run this script on the control plane - Kubernetes does not appear to be installed on this computer."
    fi
}

function main() {
    msg=${check_installation}
    if [[ ! -z msg ]]; then
        echo $msg
    elif [[ $(pgrep kube-apiserver) ]]; then
        renew_unexpired_certificate containers
    else
        renew_expired_certificate
    fi
}

main