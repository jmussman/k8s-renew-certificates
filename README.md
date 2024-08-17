[//]: # (README.md)
[//]: # (Copyright © 2024 Joel A Mussman. All rights reserved.)
[//]: #

![Banner Light](./.assets/banner-renew-k8s-certificates-light.png#gh-light-mode-only)
![banner Dark](./.assets/banner-renew-k8s-certificates-dark.png#gh-dark-mode-only)

# Renew Kubernetes Certificates

## Overview

The certificates that Kubernetes uses to authenticate nodes and the admin user expire in one year.
Instructions for renewing the certificates are difficult to find, but the process is actually simple.
The bad part is renewing the certificates requires restarting core system containers, which means
the cluster will be unavailable temporarily (usually less than 60 seconds).

This script is provided "as-is" without any warranty.
Administrators should test this in a sandbox before trying to use it in production!

This script was inspired by a [Medium blog post](https://medium.com/@sunilmalik12012/renew-expired-k8s-cluster-certificates-manually-e591ffa4dc6d)
written by Sunil Malik.
This post contained the best description and the simplest set of instructions to update the certificates.

## Configuration

1. Copy the *renew-k8s-certs.sh* file to the Kubernetes master.
1. Change the permissions on the script to execute it: chmod +x renew-k8s-certs.sh
1. Execute the script as a regular user.
Any commands requiring elevated privileges will run with sudo.
The user running the script must have permissions to sudo to root, and be prepared to enter the user password.

## Guts

The script uses *crictl* to restart the core system containers.
*crictl* requires a runtime-endpoint to be specified, Providing a default has deprecated.
The bulk of this script is to determine what the appropriate runtime-endpoint is!

The script executes these steps:
  1. Determine the runtime-endpoint.
  1. Renew the certificates.
  1. Print out the certificate expiration for a visual check.
  1. Copy the new /etc/kubernetes/admin.conf file to ~/.kube/config
  1. Restart the necessary containers: kube-apiserver, kube-scheduler, kube-controller-manager, etcd.
  1. Check the status of the pods to make sure they are restarted.
  1. Check the status of the nodes to make sure the workers are ready.

There is no requirement to touch the other nodes in the cluster, unless you are using them to issue commands
against the API (a really bad idea).
Copy the admin.conf file to the worker nodes if you feel it is necessary.



## License

The code is licensed under the MIT license. You may use and modify all or part of it as you choose, as long as attribution to the source is provided per the license. See the details in the [license file](./LICENSE.md) or at the [Open Source Initiative](https://opensource.org/licenses/MIT).


<hr>
Copyright © 2024 Joel A Mussman. All rights reserved.