# Environments

This document covers only production environments. Information about development environment can be found in [Development](./development.md#dev-environments) guide.

The Hosted Compute Image Management Service uses several external services and is deployed across multiple environments. The document outlines the architecture of each of those environments.

An overview of the deployment environments is available in the devportal: https://devportal.githubapp.com/devportal/apps/hosted-compute-ims?tab=deployenvs

![production rollout](/docs/assets/production-rollout.svg)

## Lab

The lab environment is a high fidelity environment, similar to production with a separate data tier. Lab is only addressable through the private moda network. It's similar to the development environment but each of our dependencies are spun up as separate Kubernetes pods.

Once a merge queue has been deployed to Lab environment, [E2E Lab workflow](../../.github/workflows/e2e_tests_lab.yml) is triggered automatically.
This workflow runs [E2E tests in full mode](../development.md#running-e2e-tests) against real Lab environment. If tests fail, it will block deployment to next environments. If tests pass, deployment will continue.

Resources:
- Deployment
  - Configs: `/config/kubernetes/lab`
  - API URL: http://hosted-compute-ims-lab.service.iad.github.net (only available via dev-vpn or ops-shell)
- Database:
  - Cluster: https://professorx.githubapp.com/mysql/cluster/hosted-compute-ims-db-lab
- Aqueduct
  - App name: `hosted-compute-ims-lab`
- Azure resources
  - JIT: `Azure - GitHub - Lab - Hosted Compute IMS - Contributor`
  - Azure subscriptions https://github.com/github/azure-rbac/blob/main/tf/rbac/spn-hosted-compute-ims-lab.tf
- Observability:
  - [Splunk Logs](https://splunk.githubapp.com/en-US/app/gh_reference_app/search?q=search%20index%3D%22hosted_compute_ims%22%20deployment.environment%3Dlab&sid=1710258503.638885_0C07F8EA-84C2-4CD9-B370-A76EFE0845B3&display.page.search.mode=smart&dispatch.sample_ratio=1&workload_pool=Standard&earliest=-15m%40m&latest=now) (`index="hosted_compute_ims" deployment.environment=lab`)
  - [Datadog Dashboard](https://app.datadoghq.com/dashboard/ift-srv-5vy?fromUser=false&refresh_mode=sliding&tpl_var_kube_namespace%5B0%5D=hosted-compute-ims-internal&view=spans&from_ts=1710241588933&to_ts=1710245188933&live=true)

## Production

The production environment is the end stage live site environment hosting customer data.

Resources:
- Deployment
  - Configs: `/config/kubernetes/production`
  - API URL: `hosted-compute-ims-production.githubapp.com`
- Database:
  - Cluster: https://professorx.githubapp.com/mysql/cluster/hosted-compute-ims
- Aqueduct
  - App name: `hosted-compute-ims-production`
- Azure resources
  - JIT: `Azure - GitHub - Prod - Hosted Compute IMS - Contributor`
  - Azure subscriptions https://github.com/github/azure-rbac/blob/main/tf/rbac/spn-hosted-compute-ims-prod.tf
- Observability:
  - [Splunk Logs](https://splunk.githubapp.com/en-US/app/gh_reference_app/search?q=search%20index%3D%22hosted_compute_ims%22%20deployment.environment%3Dproduction&display.page.search.mode=smart&dispatch.sample_ratio=1&workload_pool=Standard&earliest=-15m%40m&latest=now&sid=1710258563.638937_0C07F8EA-84C2-4CD9-B370-A76EFE0845B3) (`index="hosted_compute_ims" deployment.environment=production`)
  - [Datadog Dashboard](https://app.datadoghq.com/dashboard/ift-srv-5vy?fromUser=false&refresh_mode=sliding&tpl_var_kube_namespace%5B0%5D=hosted-compute-ims-production&view=spans&from_ts=1710241588933&to_ts=1710245188933&live=true)

## Connections between IMS environments and Runner SUs

- Runner Scale Units on all rings are connected with `IMS Production` environment (Curated, Marketplace and Customer images)
- Runner Proxima Scale Units are connected to two IMS environments:
    - Runner Proxima stamps use `IMS Production` environment for Curated and Markeplace images
    - Runner Proxima stamps use `IMS Proxima` environment (separate Proxima environment for every Proxima stamp) for Customer images to ensure that customers data is located in specific region. 

This approach allows to simplify managing of Curated images and Marketplace images:
- Image-gen team doesn't need to deploy curated images to every stamp separately
- Curated image versions are not duplicated for every stamp (saving cogs)
- No need to create / manage Marketplace images list for every stamp separately.

![environment connections](/docs/assets/env-connections.svg)