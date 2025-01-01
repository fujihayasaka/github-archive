# Trust-Metadata-API (TMA) Playbook

## Table of Contents

1. [Overview](#overview)
1. [Alerts](#alerts)
1. [SLOs](#slos)
1. [ChatOps and Deployments](#chatops-and-deployments)
1. [Running Production Database Migrations](#running-production-database-migrations)
1. [Reviewing Sentry Errors](#reviewing-sentry-errors)
1. [Moda deployment configuration](#moda-deployment-configuration)
1. [Increasing Kubernetes Resources](#increasing-kubernetes-resources)
1. [Accessing the Database](#accessing-the-database)
1. [Rotating HMAC Keys](#rotating-hmac-keys)
1. [FAQ](#faq)

## Overview

Trust-Metadata-API is an API for (signed) attestations, SBOMs, and potentially more in the future.

It is developed in Go, and exposes RPC using Twirp backed by a MySQL database.

## Alerts

For playbooks related to specific alerts, see [docs/playbooks/alerts.md](playbooks/alerts/alerts.md)

## SLOs

Trust-Metadata-API SLOs can be found in the [Service Catalog](https://catalog.githubapp.com/services/trust-metadata-api/slos).

## ChatOps and Deployments

Some useful ChatOps include:

```shell
# deploys main to production Moda environment
.deploy trust-metadata-api to prod

# unlock deploy queue
.unlock trust-metadata-api

# See a list of deployments
.deployed trust-metadata-api
```

## Running Production Database Migrations

See [docs/playbooks/database-migrations-prod-skeema.md](playbooks/database-migrations-prod-skeema.md).

## Reviewing Sentry Errors

See [docs/playbooks/review-sentry-errors.md](playbooks/review-sentry-errors.md).

## Moda deployment configuration

Kubernetes deployment configuration (replicas, ENV vars, etc.) can be found in [config/kubernetes/production/deployments/trust-metadata-api.yaml](https://github.com/github/trust-metadata-api/blob/main/config/kubernetes/production/deployments/trust-metadata-api.yaml).

## Increasing Kubernetes Resources

See [docs/playbooks/increase-kubernetes-moda-resources.md](playbooks/increase-kubernetes-moda-resources.md).

## Accessing the Database

See [docs/playbooks/database-access.md](playbooks/database-access.md).

## Rotating HMAC Keys

See [docs/playbooks/rotate-hmac-keys-access.md](playbooks/rotate-hmac-keys.md).

## FAQ

**Which [data classification standard](https://thehub.github.com/security/policy-desk/standards/data-classification-standard/) should be applied to TMA data?**

Given that attestations stored in the TMA database will almost always include the name of the organization and repository where the attestation originated, TMA data should be treated according to the [restricted](https://thehub.github.com/security/policy-desk/standards/data-classification-standard/#data-classification---restricted-) data classification standard.

According to the standard, the "restricted" label applies to . . . 

> Everything and anything to do with private repos including but not limited to private repo name . . .
