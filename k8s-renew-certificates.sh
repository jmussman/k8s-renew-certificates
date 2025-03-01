#!/bin/bash
#
# renew-k8s-certs
# Copyright (c) 2024-2025 Joel A Mussman. All rights reserved.
#

admin_conf=/etc/kubernetes/admin.conf
containers=('kube-apiserver' 'kube-scheduler' 'kube-controller-manager' 'etcd')
containerd_endpoint=unix:///run/containerd/containerd.sock
docker_endpoint=unix:///var/run/docker.sock
kubelet_pki_path=/var/lib/kubelet/pki
kubelet_cert_path=$kubelet_pki_path/kubelet-client-current.pem
kubelet_option='container-runtime-endpoint'
kubernetes_cert_path=/etc/kubernetes/pki/apiserver-kubelet-client.crt
kubernetes_key_path=/etc/kubernetes/pki/apiserver-kubelet-client.key
major_cutoff=1
minor_cutoff=23

function wait_for_container_restart {
    while [[ true ]]; do   
        if [[ -z $(echo $(kubectl get pods -n kube-system 2>&1) | grep "Pending\|Failed\|Unknown") ]]; then
            break
        fi
        sleep 15
    done
}

function wait_for_broken_nodes {
    for counter in $(seq 12); do   
        if [[ ! -z $(echo $(kubectl get nodes 2>&1) | grep "NotReady") ]]; then
            return 1
        fi
        sleep 15
    done
    return 0
}

function stop_system_containers {
    cre=$1; shift
    for container in "$@"; do
        sudo crictl -r $cre stop ${container#*:} > /dev/null
    done
}

function retrieve_system_container_ids {
    container_ids=()
    for container in "${containers[@]}"; do
        container_ids=(${container_ids[@]} "$container:$(sudo crictl --runtime-endpoint $1 ps | grep $container | awk '{print $1}')") 
    done
    echo ${container_ids[@]}
}

function restart_kubernetes_system {
    IFS=' ' read -r -a container_ids <<< $(retrieve_system_container_ids) $1
    stop_system_containers $1 ${container_ids[@]} 2>&1 > /dev/null
}

function refresh_user_credentials {
    sudo cp $admin_conf ~/.kube/config
    sudo chown $(id -u):$(id -g) ~/.kube/config
}

function renew_certificates {
    sudo kubeadm certs renew all > /dev/null
    sudo kubeadm certs check-expiration
}

function kubelet_endpoint_by_version {
    kv=$(kubeadm version)
    major=$(echo $kv | sed -e 's/^.*Major:"\([[:digit:]]*\).*$/\1/g')
    minor=$(echo $kv | sed -e 's/^.*Minor:"\([[:digit:]]*\).*$/\1/g')
    if (( $major > $major_cutoff || ($major == $major_cutoff && $minor > $minor_cutoff ))); then
        echo $containerd_endpoint
    else
        echo $docker_endpoint
    fi
}

function kubelet_endpoint_by_command {
    pgrep kubelet > /dev/null && ps --no-headers -fp $(pgrep kubelet) | grep "$kubelet_option" | sed -e "s/^.*${option}=\([^ ]*\).*$/\1/g"
}

function find_runtime_endpoint {
    endpoint=$(kubelet_endpoint_by_command)
    if [[ -z $endpoint ]]; then
        endpoint=$(kubelet_endpoint_by_version)
    fi
    echo $endpoint
}

function renew_unexpired_certificate {
    cre=$(find_runtime_endpoint)
    echo "Generating new certificates."
    renew_certificates
    echo "Refreshing API credentials for the current user."
    refresh_user_credentials
    echo "Restarting Kubernetes system containers."
    restart_kubernetes_system $cre
    echo "Restarting system containers; there may be a short delay before they come online."
    wait_for_container_restart
}

function rejoin_node {
    echo "Rejoining node $1 ($2) to the cluster."
    echo "Accept the ssh key fingerprint and provide the root password."
    echo "There may be up to a two-minute delay rejoining; ignore any warnings and '...uploading crisocket: Unauthorized'."
    cmd="if [[ \$(date -d \"\$(openssl x509 -enddate -noout -in $kubelet_cert_path "
    cmd+="| cut -d = -f 2)\" +%s) -lt $(date +%s) ]]; then "
    cmd+="$(kubeadm token create --print-join-command) --ignore-preflight-errors=all > /dev/null; fi"
    ssh root@$2 "$cmd"
}

function match_worker_nodes {
    readarray -t node_list <<< "$(kubectl get nodes -o wide --no-headers)"
    for node in "${node_list[@]}"; do
        IFS=' ' read -r -a node_elements <<< "$node"
        if [[ "${node_elements[2]}" == '<none>' ]]; then
            echo ${node_elements[@]}
        fi
    done
}

function rejoin_worker_nodes {
    nodes=$(match_worker_nodes)
    if [[ ! -z "$nodes" ]]; then 
        readarray -t node_list <<< "${nodes[@]}"
        for node in "${node_list[@]}"; do
            IFS=' ' read -r -a node_elements <<< "$node"
            rejoin_node $node_elements ${node_elements[5]}
        done
    fi
}

function wait_for_kubelet_restart {
    while [[ true ]]; do   
        if [[ -z $(echo $(kubectl get pods -n kube-system 2>&1) | grep "Pending\|Failed\|Unknown") ]]; then
            break
        fi
        sleep 15
    done
}

function restart_services {
    sudo systemctl restart kubelet > /dev/null
}

function set_new_certificate {
    new_cert_filename=kubelet-client-$(date +%Y-%m-%d-%H-%M-%S).pem
    new_cert_path=$kubelet_pki_path/$new_cert_filename
    sudo cat $kubernetes_cert_path $kubernetes_key_path > /tmp/$new_cert_filename
    sudo mv /tmp/$new_cert_filename $new_cert_path
    sudo rm -f $kubelet_cert_path
    sudo ln -s $new_cert_path $kubelet_cert_path
}

function check_certificate_expiration {
    if [[ $(sudo openssl x509 -enddate -noout -in $kubelet_cert_path | cut -c10- | date +%s -f -) -gt $(date +%s) ]]; then
        echo "The kubelet client certificate has not expired."
    fi
}

function renew_expired_certificate {
    echo "Checking Kubernetes certificate status, enter the password for sudo if prompted:"
    msg=$(check_certificate_expiration)
    if [[ ! -z "$msg" ]]; then
        echo $msg
    else
        echo "Generating new certificates..."
        renew_certificates
        echo "Setting new kubelet certificate..."
        set_new_certificate
        echo "Refreshing API credentials for the current user..."
        refresh_user_credentials
        echo "Restarting kubelet service..."
        restart_services
        echo "Restarting kubelet; there may be a short delay before it comes online..."
        wait_for_kubelet_restart
        echo "Polling up to three minutes to see if there are any worker nodes that do not connect..."
        if ! wait_for_broken_nodes; then rejoin_worker_nodes; fi
    fi
}

function check_installation {
    if [[ -z $(which crictl) || -z $(which kubeadm) || -z $(which kubectl) ]]; then
    	echo "Run this script on the control plane - Kubernetes does not appear to be installed on this computer."
    fi
}

function main {
    echo "Checking installation..."
    msg=${check_installation}
    if [[ ! -z "$msg" ]]; then
        echo $msg
        exit
    elif [[ "$1" != "-f" && "$1" != "--force" ]]; then
        echo "Checking Kubernetes certificate status, enter the password for sudo if prompted:"
        msg=$(check_certificate_expiration)
        if [[ ! -z "$msg" ]]; then
            echo $msg
            exit
        fi
    elif [[ $(pgrep kube-apiserver) ]]; then
        renew_unexpired_certificate containers
    else
        renew_expired_certificate
    fi
}

main $@
