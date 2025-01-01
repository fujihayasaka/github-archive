## Production Details

*How this app is deployed, how traffic flows to it.*

### How this app is deployed

This app's deployment configuration lives in this repo at [config/moda/deployment.yaml](https://github.com/github/launch/blob/master/config/moda/deployment.yaml). It specifies two production environments: `production` and `lab`.

For production, we use multiple **Kubernetes** clusters, and allow the Delivery team to define which ones those are for us by using specifying that we require a cluster with `general` functionality and within the `iad` region - the specific sites in which the application runs are opaque to us beyond these parameters. These kubernetes clusters run all resources in `config/kubernetes/<environment>` in this repo, including the Deployment and Service configurations for launch's servers and the Service which defines a load balancer. Each service defines a lookup mechanism to know which pods to send traffic to, and on which ports.

### How traffic flows to it

Traffic for the `launch-receiver` service flows through `launch-receiver.githubapp.com` (DNS is auto-configured by Moda). Traffic hits GLB, then a kubernetes load balancer pod, then our `launch-receiver` pods. This traffic is considered external, and our current known clients are Hookshot (GitHub's hooks service) and GCB (for stats reporting). Lab is the same way, just with `-lab` as a suffix. The domain name and LB type is defined in the respective Service yaml files.

Internally-addressible-only services, such as `launch-deployer` are slightly different. Their pods are defined the same, but they have two different load balancer types: one for HTTP/1.x traffic, and one for HTTP/2.x traffic (primarily gRPC). The domain name and LB configuration are all kept in our repo in the kubernetes Service yaml files.
