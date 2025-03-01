[//]: # (README.md)
[//]: # (Copyright © 2024-2025 Joel A Mussman. All rights reserved.)
[//]: #

![Banner Light](https://raw.githubusercontent.com/jmussman/cdn-fun/main/banners/banner-k8s-renew-certificates-light.png#gh-light-mode-only)
![Banner Light](https://raw.githubusercontent.com/jmussman/cdn-fun/main/banners/banner-k8s-renew-certificates-dark.png#gh-dark-mode-only)

# Renew Kubernetes Certificates

## Overview

The self-signed certificates that Kubernetes uses to authenticate nodes and the admin user expire in one year.
Instructions for renewing the certificates obscure, but the process is actually simple.
Renewing the certificates in a running requires restarting core system containers, which means
the cluster will be unavailable temporarily (usually less than 60 seconds).

An edge-case that has presented itself in classroom environments
is where lab computers with an old, frozen image
has certificates which have passed their expiration when the computers are started.
In this case, Kubernetes will not start.
Here is an example taken from /var/log/syslog on an Ubuntu server
indicating the problem with the certificates (scroll horizontally):
```
Dec  3 10:01:21 master kubelet[11127]: E1203 10:01:21.970450   11127 bootstrap.go:265] part of the existing bootstrap client certificate in /etc/kubernetes/kubelet.conf is expired: 2024-06-11 17:17:20 +0000 UTC
```
Letting the certificates expire should never be allowed to happen in a production environment.
This problem is a little more complex to solve.
There are two parts to this script, one updates existing certificates that have not expired
and the other detects that
Kubernetes is not running because of an expired certificate and fixes that.

## Utilization

Use this script on a running cluster to renew the certificates and push them out to the nodes.

1. Copy the *8s-renew-certificates.sh* file to the Kubernetes control plane node.
1. Change the permissions on the script to execute it:
    ```
    $ chmod +x k8s-renew-certificates.sh
    ```
1. Execute the script as a regular user.
The script will exit if the certificates have not expired, use --force to force a rotation:
    ```
    $ k8s-renew-certificates.sh --force

The script will automatically detect if the first mode (renew current certificates) or the
second mode (fix expired certificates) needs to be performed.

Any commands requiring elevated privileges will run with sudo.
The user running the script must have permissions to sudo to root,
be prepared to enter the user password.

In the second mode if worker nodes have expired certificates they will need to be re-joined
to the cluster.
In this case the root password for the worker node computer is required.

## Script Internals

### Mode 1 - Renew current certificates

When a running cluster is detected, which is before the current certificates actually expire,
the script will use *Docker* or *crictl* to restart the core system containers.
The choice depends on what the cluster is using for the containers.

*crictl* requires a runtime-endpoint to be specified.
Providing a default has been deprecated in later versions of Kubernetes, it should be found
in the /etc/kubernetes/kubelet.conf file where it will be read by the script.
Otherwise it must be entered manually into the script.

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
Worker nodes should rotate their own certificates as long as they are up.

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

After restarting the server, the worker nodes will appear to be Ready even if the certificates
have expired.
THe script builds in a wait of up to three minutes to see if the status changes to NotReady and
then launches the ssh commands to make them rejoin the cluster.

It should be possible to fix the certificates in the worker nodes without forcing a rejoin, according to these blog and doc pages:

* https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/troubleshooting-kubeadm/#kubelet-client-cert
* https://github.com/kubernetes-sigs/kind/issues/3492

Unfortunately it seems really difficult to get this to work, re-joining seems to be the simpler
option/


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