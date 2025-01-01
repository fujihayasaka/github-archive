# Increase Kubernetes/Moda Resources

## Background

The Trust Metadata API runs on [Moda](../kubernetes-and-moda.md) with Kubernetes as the runtime platform. If you need to increase the resources for the service, you can do so by updating the Kubernetes manifests using Kustomize.

## Process for Modifying Resources

- Locate the Kustomize Kubernetes base deployment manifest (`config/kustomize/base/deployment.yaml`) in the [config](../../config/kustomize/base) directory.
- Update the `resources` section of the manifest to increase the resources for the service:

```yaml
# config/kustomize/base/deployment.yaml
# ...
resources:
  requests:         # <-- [Minimum Resources]
    cpu: "0.5"      # <-- Change This Value
    memory: "128Mi" # <-- Change This Value
  limits:           # <-- [Maximum Resources]
    cpu: "1.5"      # <-- Change This Value
    memory: "384Mi" # <-- Change This Value
# ...
```

- See the [Kubernetes documentation](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/#resource-units-in-kubernetes) for more information on resource units.

## Process for Modifying Replicas

If you need to increase the number of replicas for the service, you can do so by updating the Kustomize overlay. This allows you to scale the service horizontally to handle more traffic.

- Locate the environment-specific Kustomize overlay (`config/kustomize/overlays/<staging|production|other>/patches/container-patch.yaml`) in the [config](../../config/kustomize/overlays) directory.
- Add or update the `replicas` field in the patch file to increase the number of replicas for the service:

```yaml
spec:
  replicas: 2 # <-- Change This Value
```

- See the [Kubernetes documentation](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#scaling-a-deployment) for more information on scaling a deployment.

## Deployment

- Once you have updated the manifest, build the Kubernetes manifests with `gh kustomize build` and commit the changes.
- When the changes are approved, deploy the changes to the Moda environment by running the deploy command in [`#package-security-ops`](https://github.slack.com/archives/C037TJZGCGN):

```shell
.deploy https://github.com/github/trust-metadata-api/pull/<YOUR_PR_NUMBER> to <staging|production>
```

Merge the PR once the deployment is complete and confirmed to be working.
