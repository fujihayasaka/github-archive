# Proxima Cheatsheet for Authnd

`authnd` is deployed to all Proxima stamps, in much the same way that it is deployed to Dotcom.  However, there are notable differences in the architecture and observability resources which we want to highlight here.

## Table of Contents

- [Key Differences](#key-differences)
- [Cheatsheet](#cheatsheet)
  - [Web Access](#web-access)
  - [Observability](#observability)
  - [ProdShell resources](#prodshell-resources)
    - [Rails console](#rails-console)
    - [DB console](#db-console)
    - [Vault](#vault)
    - [Kubernetes](#kubernetes)
- [Onboarding to a new stamp](#onboarding-to-a-new-stamp)
- [References](#references)

## Key Differences

General architecture differences:

- All stamp infrastructure is hosted in the Azure Kubernetes Service (AKS), with 3 availability zones (i.e. clusters) per stamp[^1].
  - Primary purpose is to provide data residency (DR).
- All tables share a single, Azure-hosted MySQL cluster with different schemas for each Dotcom cluster and schema.[^2]
- Logs flow to Splunk in different regions based on DR requirements.

[^1]: Many more [details on TheHub](https://thehub.github.com/epd/engineering/products-and-services/proxima/comparison-with-dotcom/).

[^2]: Subject to change based on usage, performance, scale, etc. at a later date.

Specific to authnd:

  - We maintain direct read-only connections to the `github_production` schema in each stamp's cluster (_think mysql1_).
- `authnd` does not require HMAC auth, instead using Istio's ServiceMesh authorization to [allowlist client namespaces](https://github.com/github/authnd/blob/8abddb30793c9f6374fdbad8bd24f232855acdca/config/kubernetes/prod-weu-01/servicemeshconfigs/config.yaml#L7-L11).
- `authnd` runs without Freno throttling because Freno is not present in Azure MySQL.[^4]
  - VividCortex is also not available.

[^3]: You can read more about that decision [here]().
[^4]: As of last update to this document (12/7/2023), but subject to change.

## Cheatsheet

### Web Access

There's an Okta-synced, staff tenant for each stamp. Currently, those are:

- staff-wus2-01
  - Tenant: [staffship-01](https://devportal.githubapp.com/proxima/stamps/staff-wus2-01/tenants/staffship-01)
  - URL: <https://staffship-01.ghe.com/>
- prod-weu-01
  - Tenant: [octodemo-eu](https://devportal.githubapp.com/proxima/stamps/prod-weu-01/tenants/octodemo-eu)
  - URL: <https://octodemo-eu.ghe.com/>

As new stamps are added, you can find that information on [DevPortal](https://devportal.githubapp.com/proxima/stamps) and in [the Proxima repo docs](https://github.com/github/proxima/blob/main/docs/tenants.md).

### Observability

Logs are dependent on stamp's geo:

- dotcom: <https://splunk.githubapp.com/>
- staff-wus2-01: <https://splunk.githubapp.com/>
- prod-weu-01: <https://splunk-eu.githubapp.com/>

All metrics and traces go to the [shared DataDog instance](https://app.datadoghq.com/).

All exceptions go to the [shared Sentry instance](https://github.sentry.io/).

### ProdShell resources

All stamps are accessible from the [usual prodshell hosts](https://thehub.github.com/security/security-operations/production-shell-access/).

#### Rails console

Accessible like normal but requires you to provide the stamp name. Example for staffship:

```
gh-console staff-wus2-01
```

#### DB console

Accessible like normal, but you must specify a replica name ([discoverable in ProfessorX](https://professorx.githubapp.com/mysql/cluster/staffship)). Example for staffship:

```
gh-dbconsole db-mysql-2462e39.staff-wus2-01-az1
```

#### Vault

The existing shared Vault instance is used for all stamps, with one "environment" per stamp for each app. For example, this will list all authnd secrets in Proxima staffship:

```
vault-secret -a authnd -e staff-wus2-01
```

#### Kubernetes

Here is how you can access k8s clusters for each stamp (3 AZs per stamp):

```
gh-kubeconfig
kubectl --context proxima-1-staff-wus2-01-az1 -n authnd-staff-wus2-01 get pods
```

For now, all Proxima clusters follow the pattern `proxima-1-%stamp%-az[1-3]`.

Authnd is deployed to the `authnd-%stamp%` namespace in each cluster.

## Onboarding to a new stamp

📢 [Detailed guide is maintained here](https://github.com/github/authnd/blob/proxima-cheatsheet/docs/proxima-stamp-onboarding.md)

## References

[[TheHub] Proxima vs Dotcom comparison](https://thehub.github.com/epd/engineering/products-and-services/proxima/comparison-with-dotcom/)

[[TheHub] Observability in Proxima](https://thehub.github.com/epd/engineering/products-and-services/proxima/observability/)
