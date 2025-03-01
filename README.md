[//]: # (README.md)
[//]: # (Copyright © 2024-2025 Joel A Mussman. All rights reserved.)
[//]: #

![Banner Light](https://raw.githubusercontent.com/jmussman/cdn-fun/main/banners/banner-k8s-renew-certificates-light.png#gh-light-mode-only)
![Banner Light](https://raw.githubusercontent.com/jmussman/cdn-fun/main/banners/banner-k8s-renew-certificates-dark.png#gh-dark-mode-only)

# Renew Kubernetes Certificates

## Overview

Go to the section on [Utilization](#utilization) for how to use the scripts.

Kubernetes uses self-signed certificates for cluster-internal authentication and communication.
It is its own certificate authority, so it accepts the certificates that it signed for
the *kubelet* service running on the nodes, and users calling the API through *kubectl*.
There are plenty of third-party certificate management solutions that may be overlayed on
Kubernetes, but what if you are not using that?
The CA certificate that Kubernetes creates will expire ten years after the installation,
renewing it addressed here: [https://kubernetes.io/docs/tasks/tls/manual-rotation-of-ca-certificates/](https://kubernetes.io/docs/tasks/tls/manual-rotation-of-ca-certificates/).

When a *kubelet* service is joined to the cluster the administrator is vouching for it,
and it gets a certificate to use for authenticating with the control plane.
These certificates expire on one year.
To handle this, the kubelet service, which is already talking to the control plane,
should configured to get a new certificate from the CP before it expires:
[https://kubernetes.io/docs/tasks/tls/certificate-rotation/](https://kubernetes.io/docs/tasks/tls/certificate-rotation/).

If the kubelet certificate expires the node will become "NotReady".
There are several articles that address forcing a renewal including this note in the Kubernetes
documentation: [https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/troubleshooting-kubeadm/#kubelet-client-cert](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/troubleshooting-kubeadm/#kubelet-client-cert).
But, it is easier just to rejoin the node to the cluster which will force a new certificate.
The [*k8s-rejoin-node.sh*](#k8s-rejoin-nodesh) script in this project will force a rejoin of a node with an expired certificate.

Managing the certificates used by the control plane is well documented:
[https://kubernetes.io/docs/reference/setup-tools/kubeadm/kubeadm-certs/](https://kubernetes.io/docs/reference/setup-tools/kubeadm/kubeadm-certs/).
If you are in a scenarion where Kubernetes will not start the control plane because the certificates
has expired, renewing them will allow the CP to be started.
Here is an example taken from /var/log/syslog on an Ubuntu server
showing the problem with the certificates (it scrolls horizontally):
```
Dec  3 10:01:21 master kubelet[11127]: E1203 10:01:21.970450   11127 bootstrap.go:265] part of the existing bootstrap client certificate in /etc/kubernetes/kubelet.conf is expired: 2024-06-11 17:17:20 +0000 UTC
```

*kubeadm certs renew* will update the certificates, and tell you that you need to restart four containers in
the *kube-system* namespace: *kube-apiserver*, *kube-scheduler*, *kube-controller-manager*, *etcd*.
If you are using the */etc/kubernetes/admin.conf* file as the credentials for a "super-admin" user you
will need to refresh their credentials in their ~/.kube/config file because admin.conf has been updated.

Our [*k8s-renew-certificates*](#k8s-renew-certificates) script will take care of all of this regardless of
whether Kubernetes starts or not.

## Utilization

### k8s-rejoin-node.sh

This script will use ssh to initiate a rejoin operation on a node,
one step of the operation performed by the renewal script.
This will only work if the node is NotReady and the Kubelet certificate has expired.
Download the script (you can do it directly with curl)
and execute it with bash as a non-root user with the Kubernetes node name.
You will need the root password for the node.
```
curl --remote-name https://raw.githubusercontent.com/jmussman/k8s-renew-certificates/refs/heads/main/k8s-rejoin-node.sh
```
```
bash k8s-rejoin-node.sh <node name>
```

### k8s-renew-certificates

This script handles three situations:

* Renew the certificates in a stable Kubernetes control plane (use -f or --force)
* Renew the certificates in a running Kubernetes CP where they have expired
* Renew the certificate and start a stopped Kuberenetes CP with expired certificates

Download the script and run it with bash as a non-root user that has super-admin
access to the cluster (the /etc/kubernetes/admin.conf file was copied to ~/.kube/config).
Add -f or --force if this is a stable Kubernetes CP with unexpired certificates.
```
curl --remote-name https://raw.githubusercontent.com/jmussman/k8s-renew-certificates/refs/heads/main/k8s-renew-certificates.sh
```
```
bash k8s-renew-certificates.sh
```

## Script Internals

### k8s-rejoin-node

This script executes a *kubeadm token create --print-join-command* to get the join command.
Then it executes a command remotely on the node using ssh to run that join command,
but only if the certificate for the kubelet has expired.

### Mode 1 - Renew current certificates

When a running cluster is detected, which is before the current certificates actually expire,
the script will use *Docker* or *crictl* to restart the core system containers.
The choice depends on what the cluster is using for the containers.

*crictl* requires a runtime-endpoint to be specified.
Providing a default has been deprecated in later versions of Kubernetes, the path should be found
as the *containerRuntimeEndpoint* attribute in the /etc/kubernetes/kubelet.conf file
where it will be read automatically by the script.
If the path is not there it must be entered manually into the script.

In this mode the script executes these steps:

1. Renew the certificates.
1. Print out the certificate expiration for a visual check.
1. Refresh the user credentials: copy the new /etc/kubernetes/admin.conf file to ~/.kube/config.
1. Determine *Docker* or *crictl*, and if crictl the runtime-endpoint.
1. Restart the necessary containers: kube-apiserver, kube-scheduler, kube-controller-manager, etcd.
1. Check the status of the nodes to make sure the everything ready.

There is no requirement to touch the other nodes in the cluster, unless you are using them
to use *kubectl* against the API (a really bad idea), in which case the user credentials need
to be reset.
The new certificates will propogate automatically to the nodes.
Worker nodes should rotate their own certificates as long as they are up
and configured to do so.

### Mode 2 - Fix expired certificates

When the certificates have already passed expiration Kubernetes will refuse to start
on the control plane node.
In order to fix this, new certificates have to be generated, copied into place for
the *kubelet* client certificate, and the worker nodes rejoined.

The script executes these steps:

1. Verify an expired certificate is the problem and show the expiration of the current certificate.
1. Renew the certificates.
1. Copy the new certificate to the Kublet configuration.
1. Start Kubernetes.
1. Refresh the user credentials: copy the new /etc/kubernetes/admin.conf file to ~/.kube/config.
1. Identify the worker nodes and use an ssh command to rejoin each one.

#### Notes:

After restarting the server if you run *kubectl get nodes* the worker nodes will appear
to be *Ready* even if the certificates have expired; this state usually lasts about
sixty seconds and then they go to *NotReady* because they cannot connect.

THe script builds in a wait of up to three minutes to see if any nodes change to *NotReady* and
then launches the ssh commands to make them rejoin the cluster.

## Credits

This k8s-renew-certs.sh script was inspired by a [Medium blog post](https://medium.com/@sunilmalik12012/renew-expired-k8s-cluster-certificates-manually-e591ffa4dc6d)
written by Sunil Malik.
This post contained the best description and the simplest set of instructions to update the certificates that I found.

## See Also

* The Kubernetes installation scripts for various platforms at https://github.com/jmussman/k8s-install-scripts

## License

The code is licensed under the MIT license. You may use and modify all or part of it as you choose, as long as attribution to the source is provided per the license. See the details in the [license file](./LICENSE.md) or at the [Open Source Initiative](https://opensource.org/licenses/MIT).


<hr>
Copyright © 2024-2025 Joel A Mussman. All rights reserved.