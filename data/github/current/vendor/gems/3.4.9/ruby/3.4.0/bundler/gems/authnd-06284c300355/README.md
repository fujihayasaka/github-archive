# authnd

## What is Authnd?

[Authnd](https://github.com/github/authnd) (auth-en-dee) is an authentication service for GitHub.
It accepts [credentials](proto/authentication/v0/credentials.proto) from clients and resolves them into a set of [attributes](proto/authentication/v0/attributes.proto) describing the user.

It's also the future of authentication at GitHub.

For more information, view our documentation on [The Hub](https://thehub.github.com/engineering/development-and-ops/authentication/authnd).

## Client Libraries

Client documentation is found on [The Hub](https://thehub.github.com/engineering/development-and-ops/authentication/authnd#client-libraries).

## Operational metrics

- Gaze at [our dashboard](https://app.datadoghq.com/dashboard/nu7-a4k-jza)
- Observe our [Sentry exceptions](https://sentry.io/organizations/github/issues/?project=5391058)
- Peruse our [Splunk logs](https://splunk.githubapp.com/en-US/app/gh_reference_app/search?q=search%20index%3Dcatchall%20kube_namespace%3Dauthnd-production%20level%3DERROR): `index=catchall kube_namespace=authnd-production level=ERROR`
- Eye [our Service Catalog](https://catalog.githubapp.com/services/authnd)
- See [our SLOs in Datadog](https://app.datadoghq.com/slo?query=authnd)
- Look at [our monitors in Datadog](https://app.datadoghq.com/monitors/manage?q=authnd)

## Development process :hammer:

:information_source:&nbsp;&nbsp;[Authentication Team Project Board](https://github.com/orgs/github/projects/1619)

:keyboard:&nbsp;&nbsp;[Development guide](docs/authnd-development.md)

:office:&nbsp;&nbsp;[Authnd in enterprise environments information](docs/authnd-enterprise.md)

## Context & Documentation
* [Security Review](https://github.com/github/security-reviews/issues/218)
* [Authentication Areas of Responsibility Docs](https://github.com/github/authentication/tree/main/docs/aor#our-area-of-responsibility-aor)
* [Service Playbook](https://github.com/github/ops/blob/master/docs/playbooks/authnd/index.md)
* [mysql1 impact summary](https://gist.ghe.io/dbussink/fc8856464f597ef46decb56b9003526f)
* [git systems overview](https://gist.github.com/bscofield/d379078d3de99d162d02025ba6f71602)
* [Modern Authentication](https://docs.google.com/document/d/1LiwgIC5NBqsOpb5BcTpKekEI0LfNejjmfJvfQ_XXEr8/edit#)
  - Working document from Wall-e time-period to discuss some initiatives an authn team could take on
* For more `authn` team specific documentation and ADRs checkout [`docs/`](docs/)
* The authnd-producer project can be found [here](https://github.com/github/authnd-producer)
## Team

This project is owned by [github/authentication](https://github.com/github/authentication)
