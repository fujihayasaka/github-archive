# Dependency Graph playbooks

Dependency Graph playbooks live in the https://github.com/github/ops repository, in the `docs/playbooks/dependency-graph` [directory](https://github.com/github/ops/tree/master/docs/playbooks/dependency-graph/).
Playbooks are here as it's a centralised location for all GitHub playbooks and the repository is accessible when GitHub is down, via mirrors.
Also avoids duplicating information that is common to all DG services.

These playbooks are designed to be helpful to a First Responder investigating an issue.

When creating playbooks please see our team [Playbook Guide](https://github.com/github/dependency-graph/blob/main/docs/operating-manual/playbook-guide.md)

## Dependency Graph API playbooks

- [Dependency Graph API](https://github.com/github/ops/blob/master/docs/playbooks/dependency-graph/dependency-graph-api.md) Playbook for this service
- [Spokes Certificate Expiration](https://github.com/github/ops/blob/master/docs/playbooks/dependency-graph/playbooks/monitors/spokesd-cert-expiration.md)
- [Job Queues](https://github.com/github/ops/blob/master/docs/playbooks/dependency-graph/playbooks/job-queues.md) with instructions how to pause, throttle and deal with offset issues.

## Overview
Dependency Graph contains playbooks for our [API](api.md) (used on github/github) as well as
for our [workers](workers.md) (in charge of populating dependency graph data such as package releases).

Despite the repository being called `dependency-graph-api`, API and workers live in this repository, being deployed to different environments.

## Quick Links
- [API Playbook](api.md)
- [Workers Playbook](workers.md)
- [Go modules](go.md)
- [GHES/AE](ghex.md)
