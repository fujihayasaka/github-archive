# 22. Use official Maxwell docker images

Date: 2021-01-12

## Status

Accepted

## Context

Maxwell will have access to all of our _unencrypted_ data in the databases it replicates from.
Since we did not write Maxwell, it is important that we understand and trust what it is doing.
Specifically, we have to decide exactly how we will run Maxwell.
There are two viable options here:

1. Fork the zendesk/maxwell GitHub repo to github/maxwell, investigate the code, and build our own image.
2. Use the official [Maxwell docker image](https://hub.docker.com/r/zendesk/maxwell) and trust that it matches a build from the GitHub source.
3. A hybrid approach: Use our own Docker build and the official Java binaries from the GitHub repo (e.g. https://github.com/zendesk/maxwell/releases/tag/v1.29.1)

In addition, we have the option of applying additional protections such as Kubernetes Network Policies to ensure Maxwell can't send our data to an unexpected recipient.

Maxwell was in use previously at GitHub as part of data pipelines work, so we know it is not completely new to GitHub and has been used with production data before.

## Decision

We will use the official Maxwell docker image published by Zendesk: `zendesk/maxwell`.
We will create Kubernetes Network Policies as feasible to restrict access to external services.

## Consequences

The official docker image is linked from the GitHub repository (https://github.com/zendesk/maxwell ; via the website http://maxwells-daemon.io/) and the GitHub repository belongs to a "verified" org on GitHub for Zendesk.
We trust a lot of third-party services and components with our data, and vetting the code directly would be a lot of work to reduce the risk only minimally (since we could easily miss something).
Using a tool like Network Policies to prevent the egress of data feels like a more complete solution.

Using official images means we don't need to react to updates by updating our fork.
We're also more able to get support from the Maxwell community.

We always have the option to switch to building our own image when we identify a need for it.
