#!/bin/bash
#
# renew-k8s-certs
# Copyright (c) 2024-2025 Joel A Mussman. All rights reserved.
#

containers=('kube-apiserver' 'kube-scheduler' 'kube-controller-manager' 'etcd')
criEndpoint=unix:///run/containerd/containerd.sock
dockerShimEndpoint=unix:///var/run/dockershim.sock
majorCutoff=1
minorCutoff=23
option='--container-runtime-endpoint'
kubletCertificateFile=/var/lib/kubelet/pki/kubelet-client-current.pem

function show_node_status() {
    kubectl get nodes
}

function kubelet_endpoint_by_command() {
    pgrep kubelet > /dev/null && ps --no-headers -fp $(pgrep kubelet) | grep "$option" | sed -e "s/^.*${option}=\([^ ]*\).*$/\1/g"
}

function kubelet_endpoint_by_version() {
    kv=$(kubeadm version)
    major=$(echo $kv | sed -e 's/^.*Major:"\([[:digit:]]*\).*$/\1/g')
    minor=$(echo $kv | sed -e 's/^.*Minor:"\([[:digit:]]*\).*$/\1/g')
    if (( $major > $majorCutoff || ($major == $majorCutoff && $minor > $minorCutoff ))); then
        echo $criEndpoint
    else
        echo $dockerShimEndpoint
    fi
}

function find_runtime_endpoint() {
    endpoint=$(kubelet_endpoint_by_command)
    if [[ -z $endpoint ]]; then
        endpoint=$(kubelet_endpoint_by_version)
    fi
    echo $endpoint
}

function renew_certificates() {
    sudo kubeadm certs renew all
    sudo kubeadm certs check-expiration
}

function refresh_user_credentials() {
    sudo cp /etc/kubernetes/admin.conf ~/.kube/config
    sudo chown $(id -u):$(id -g) ~/.kube/config
}

function retrieve_system_container_ids() {
    containerIds=()
    for container in "$@"; do
        containerIds=(${containerIds[@]} "$container:$(sudo crictl --runtime-endpoint $cre ps | grep $container | awk '{print $1}')") 
    done
    return containerIds
}

function stop_system_containers() {
    echo "Stopping system containers"
    for container in "$@"; do
        sudo crictl --runtime-endpoint $cre stop ${container#*:} > /dev/null
    done
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

function restart_kubernetes_system {
    containerIds = retrieve_container_ids $@
    stop_system_containers @containerIds
    wait_for_restart()
}

function renew_unexpired_certificate {

}

function renew_expired_certificate {

}

function rejoin_worker_node {

}

function check_certificate_expiration() {
    if [[ $(sudo openssl x509 -enddate -noout -in $kubeletCertificateFile | cut -c10- | date +%s -f -) -gt $(date +%s) ]]; then
        echo "The kubelet client certificate has not expired, this is not a problem this script can fix!"
    fi
}

# Is Kubernetes installed?

if [[ -z $(which crictl) || -z $(which kubeadm) || -z $(which kubectl) ]]; then

	echo "Commands are missing, Kubernetes does not appear to be installed."

	exit 1
fi

if [[ $(pgrep kube-apiserver) ]]; then

    renew_unexpired_certificate containers
    find_runtime_endpoint
    renew_certificates
    refresh_user_credentials
    restart_kubernetes_system
    show_node_status

else

    msg=$(check_certificate_expiration)
    if [[ -z $msg ]]; then
        sudo kubeadm certs renew all
        newCertificateDate="$(date +'%Y-%m-%d-%H-%M-%S').pem"
        newCertificateFile="/var/lib/kubelet/pki/kubelet-client-${newCertificateDate}"
        sudo cat /etc/kubernetes/pki/apiserver-kubelet-client.crt /etc/kubernetes/pki/apiserver-kubelet-client.key > "/tmp/${newCertificateDate}"
        sudo mv "/tmp/${newCertificateDate}" "${newCertificateFile}"
        sudo rm -f /var/lib/kubelet/pki/kubelet-client-current.pem
        sudo ln -s $newCertificateFile /var/lib/kubelet/pki/kubelet-client-current.pem

        sudo systemctl restart kubelet

        refresh_user_credentials
    fi
fi

# Save the join command to rejoin the nodes.

joinCommand=$(kubeadm token create --print-join-command)

readarray -t nodelist <<<"$(kubectl get nodes -o wide --no-headers)"

for node in "${nodelist[@]}"; do

    # Break each node apart at the spaces, we only care about elements 0, 1, 2, and 5
    # so following element values that may have spaces are not an issue.

    nodestripped=$(echo "$node" | tr -s ' ')
    readarray -d ' ' -t nodeelements <<<"$nodestripped"
    echo "Checking node ${nodeelements[0]}@(${nodeelements[5]} status: ${nodeelements[1]}"

    if [[ "${nodeelements[1]}" == 'NotReady' && "${nodeelements[2]}" == '<none>' ]]; then

        # This is a worker node that has lost connection because of the certificates.

        ipaddress=${nodeelements[5]}

        # Run the join command on each node; running this on a node previously joined will
        # hang for a minute or too. Be patient on each node.

        echo "Rejoining node ${nodeelements[0]} ($ipaddress) to the cluster;" \
            "be prepared with the root password:"
        echo "ssh root@${ipaddress} \"$joinCommand --ignore-preflight-errors=all\""

        ssh root@${ipaddress} "$joinCommand --ignore-preflight-errors=all"
    fi
done

echo
echo "Finished"