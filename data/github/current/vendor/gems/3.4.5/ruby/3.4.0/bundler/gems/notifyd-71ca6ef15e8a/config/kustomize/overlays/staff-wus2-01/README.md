# staff-wus2-01

This environment is deployed to older architecture in which there is a single Kubernetes cluster for each of the three availability zones.
Deployment replicas should be adjusted to compensate for this, as necessary.

The new architecture consists of three clusters per availability zone, for a total of nine clusters.

# Ref

https://github.com/github/proxima/blob/main/adr/kubernetes-three-clusters-per-az.md
