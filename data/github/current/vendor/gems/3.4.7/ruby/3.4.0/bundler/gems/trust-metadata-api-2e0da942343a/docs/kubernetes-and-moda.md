# Kubernetes and Moda

## Moda

The TMA service uses Moda which is a GitHub specific runtime platform used for deploying services. Currently, Moda uses Kubernetes as the runtime platform.

You can read more about it at [The Hub - Moda](https://thehub.github.com/epd/engineering/products-and-services/internal/moda/).

## Kubernetes

Kubernetes is a container orchestration system. It is used to manage the lifecycle of containers. It is used to deploy, scale, and manage containerized applications.

You can read more about GitHub's K8s usage at [The Hub - Kubernetes](https://thehub.github.com/epd/engineering/products-and-services/internal/moda/feature-documentation/kube-configs/).

We manage the Trust-Metadata-API service with Kubernetes. The Kubernetes manifests are located in the [config](../config/kubernetes/) directory but are managed using Kustomize. See below for more information on Kustomize.

For additional information about resource management, see [The Hub - Demystifying Kubernetes Requests & Limits](https://thehub.github.com/epd/engineering/dev-practicals/containers/container-runtime/requests-and-limits/) and [The Hub - Tuning resource usage](https://thehub.github.com/epd/engineering/products-and-services/internal/moda/reference/tuning-resource-usage/).

## Kustomize

Kubernetes resources are managed with Kustomize in the [config](./config/) directory.
The `gh` CLI tool has a [kustomize extension](https://github.com/github/gh-kustomize/tree/main) for generating Kubernetes resources from Kustomzie for the the Moda environment. This includes generating manifests into directories that are recognized by Moda.

Building new Kubernetes manifests can be done with `gh kustomize build`. More
information around commands can be found [here](https://github.com/github/gh-kustomize/tree/main).

For more information, see [The Hub - Kustomize](https://thehub.github.com/epd/engineering/products-and-services/internal/moda/kustomize/).
