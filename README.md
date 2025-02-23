[//]: # (README.md)
[//]: # (Copyright © 2024-2025 Joel A Mussman. All rights reserved.)
[//]: #

![Banner Light](https://raw.githubusercontent.com/jmussman/cdn-fun/main/banners/banner-k8s-renew-certificates-light.png#gh-light-mode-only)
![Banner Light](https://raw.githubusercontent.com/jmussman/cdn-fun/main/banners/banner-k8s-renew-certificates-dark.png#gh-dark-mode-only)

# Renew Kubernetes Certificates

## Overview

The self-signed certificates that Kubernetes uses to authenticate nodes and the admin user expire in one year.
Instructions for renewing the certificates are difficult to find, but the process is actually simple.
The bad part is renewing the certificates requires restarting core system containers, which means
the cluster will be unavailable temporarily (usually less than 60 seconds).

A edge-case that has presented itself in classroom environments is where lab computers with an old, frozen image
has certificates which have passed their expiration.
In this case, Kubernetes will not even start as a service!
Here is an example taken from /var/log/syslog on an Ubuntu server (scroll horizontally):
```
Dec  3 10:01:21 master kubelet[11127]: E1203 10:01:21.970450   11127 bootstrap.go:265] part of the existing bootstrap client certificate in /etc/kubernetes/kubelet.conf is expired: 2024-06-11 17:17:20 +0000 UTC
```
Letting the certificates expire should never be allowed to happen in a production environment.
This problem is a little more complex to solve, so there is a whole second part to the script
which detects that Kubernetes is not running because of an expired certificate and fixes that.

## Utilization

Use this script on a running cluster to renew the certificates and push them out to the nodes.

1. Copy the *8s-renew-certificates.sh* file to the Kubernetes control plane node.
1. Change the permissions on the script to execute it:
    ```
    $ chmod +x k8s-renew-certificates.sh
    ```
1. Execute the script as a regular user.

The script will automatically detect if the first mode (renew current certificates) or the
second mode (fix expired certificates) needs to be performed.

Any commands requiring elevated privileges will run with sudo.
The user running the script must have permissions to sudo to root, and be prepared to enter the user password.

## Script Internals

### Mode 1 - Renew current certificates

When a running cluster is detected, which is before the current certificates actually expire,
the script will use *crictl* to restart the core system containers.
*crictl* requires a runtime-endpoint to be specified.
Providing a default has been deprecated in later versions of Kubernetes.
The bulk of the first half of the script is to determine what the appropriate runtime-endpoint is!

The script executes these steps:

1. Determine the runtime-endpoint.
1. Renew the certificates.
1. Print out the certificate expiration for a visual check.
1. Copy the new /etc/kubernetes/admin.conf file to ~/.kube/config
1. Restart the necessary containers: kube-apiserver, kube-scheduler, kube-controller-manager, etcd.
1. Check the status of the pods to make sure they are restarted.
1. Check the status of the nodes to make sure the workers are ready.

There is no requirement to touch the other nodes in the cluster, unless you are using them
to issue commands against the API (a really bad idea).
The certificates will propogate automatically to the nodes.
Copy the admin.conf file to the user computers, or preferably to a management computer, where necessary.

### Mode 2 - Fix expired certificates

When the certificates have already passed expiration Kubernetes will refuse to start
on the control plane node.
In order to fix this, new certificates have to be generated, manually put into place for
the *kubelet* client certificate, and the worker nodes manually rejoined.

The script executes these steps:

1. Verify an expired certificate is the problem and show the expiration of the current certificate.
1. Renew the certificates.
1. Copy the new certificate to the Kublet configuration.
1. Start Kubernetes.
1. Copy the new /etc/kubernetes/admin.conf file to ~/.kube/config
1. Identify the worker nodes and use an ssh command to rejoin each one.

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