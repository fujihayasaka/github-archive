# How to use Kustomize to manage the Kubernetes configuration

Context: https://github.com/github/c2c-actions/blob/main/docs/adrs/7889-launch-configuration-with-kustomize.md

As part of preparing for Proxima stamp onboarding, Launch has adopted Kustomize to make managing Kubernetes configuration files more scalable.
Kustomize is a tool that combines base and overlay YAML files into a complete manifest to deploy resources to our Kubernetes clusters.
This document is meant to provide tips on how to navigate Launch's specific setup for Kustomize.
For general Kustomize information, please refer to the documentation provided by the Moda team.

- https://thehub.github.com/epd/engineering/products-and-services/internal/moda/kustomize/
- https://thehub.github.com/epd/engineering/products-and-services/internal/moda/kustomize/kustomize-at-github/

## Base configurations

Launch is arranged into several applications, a couple cronjobs, and a few ad-hoc jobs.
Each of these has a folder with one or more resource files as well as a `kustomization.yaml` file to specify which resources are included.
Currently the following elements are represented:

```
├── cronjobs
│   ├── launch-frequent-jobs
│   │   ├── cronjob.yaml
│   │   └── kustomization.yaml
│   ├── launch-heal-workflows
│   │   ├── cronjob.yaml
│   │   └── kustomization.yaml
│   └── launch-incomplete-workflows
│       ├── cronjob.yaml
│       └── kustomization.yaml
├── jobs
│   └── launch-transitions
│       ├── job.yaml
│       └── kustomization.yaml
├── launch-chatops
│   ├── deployment.yaml
│   ├── kustomization.yaml
│   └── service.yaml
├── launch-deployer
│   ├── deployment.yaml
│   ├── kustomization.yaml
│   └── service.yaml
├── launch-hydro-consumer
│   ├── deployment.yaml
│   ├── kustomization.yaml
│   └── service.yaml
├── launch-receiver
│   ├── deployment.yaml
│   ├── internal-service.yaml
│   ├── kustomization.yaml
│   └── service.yaml
└── launch-worker
    ├── deployment.yaml
    ├── kustomization.yaml
    └── service.yaml
```

The resource files here are best used for any attributes that are common to all stamps.
However if there are attributes that are not common but you want to include as a baseline, these attributes can be overriden in the overlays section (discussed next).

## Overlay configurations

Launch uses overlay directories to represent the various stamps or environments we deploy to.
Each stamp or environment contains at least a `kustomization.yaml` file.
This file contains references to other Kustomize directories or specific files to compose a cluster.
Let's take a look at an example:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - namespace.yaml
  - resourcequota.yaml
  - ../../base/launch-chatops
  - ../../base/launch-worker

patches:
  - path: <relative path to file containing patch>
  [ target:  # Optional target specifiers
      group: <optional group>
      version: <optional version>
      kind: <optional kind>
      name: <optional name or regex pattern>
      namespace: <optional namespace>
      labelSelector: <optional label selector>
      annotationSelector: <optional annotation selector> ]
```

In the above example we have a couple of files within the current directory that provide the `Namespace` and `ResourceQuota` resource types to the Lab environment.
In addition we add the base elements for `launch-chatops` and `launch-worker`.
This ensures that we get any resources defined by the `kustomization.yaml` file at the root of those directories.

The last piece to the above is the patches section, which we use to override values from the `launch-worker` `Deployment`.
We can override any piece from the reference except the name and the resource type itself, which are used for resource matching.
In the most common case, these are environmental variables which are often specific to the stamp.
We also tweak the CPU, memory, and replicas of the `Pods` in our `Deployment` frequently to account for traffic differences between environments.

Note: `backfills` is a special case in overlays representing MySQL transitions that are run as needed.

## Using the Kustomize tool

**Note**: The following is optional. Launch is setup to use Kustomize as part of its CI. However you may want to manually check the output

Once you've updated the Kustomize configuration, you'll need to build the Kubernetes configuration locally to pass CI.
To do this, we can use the CLI.
The full documentation is provided on the Hub:

- https://thehub.github.com/epd/engineering/products-and-services/internal/moda/kustomize/kustomize-at-github/commands/

The most basic commands are:

- `gh kustomize build`
    - This generates or updates files in `configs/kubernetes` with your changes.
    - You should be sure to validate those changes before sending for review.
- `gh kustomize validate`
    - This checks that the current configuration in `configs/kubernetes` is up-to-date based on the Kustomize directory.
    - CI will run this for you, but the command is there if you need to check locally.

## FAQ

### Where does my ENV change go?

The most common reason for adjusting Kubernetes configuration will be to update ENV.
You can try the following steps to make your updates.
If these don't work, please reach out in #launch on Slack for help.

- To find the right place to make your change, navigate to `configs/kustomize/overlays`.
- Then for each stamp you need to change, find the resource under `<env or stamp>/patches/<resource file>`
- For example, to update an ENV for launch-deployer for production, the file is `configs/kustomize/overlays/production/patches/launch-deployer-deployment.yaml`.
- Note the resource type is `Deployment` for everything except `CronJob` and `Job` resources.
- Find the `env:` or `envFrom:` section in the file and update your change
- Run `gh kustomize build`.
  - This step is optional. CI will build this for you when you push your changes.
- Validate there is the expected change in `config/kubernetes/production/deployments/launch-deployer.yaml`
- Send your PR for review when ready.
