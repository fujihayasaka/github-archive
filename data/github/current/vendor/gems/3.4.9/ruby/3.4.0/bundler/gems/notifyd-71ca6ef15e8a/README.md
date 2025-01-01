# Notifyd: Notifications Service

<img src="./docs/images/_logo.gif" width="250px">

---

Notifyd is a service for delivering notifications (web, email, push and more)
to GitHub users.

It consumes messages from aqueduct queues to deliver notifications, and
exposes a twirp API for other functionality.

---

## Docs

- [Glossary](./docs/glossary.md)
- [Notifyd customers and goals](./docs/goals.md)
- [Architecture overview](./ARCHITECTURE.md)
- [ADRs (Architecture Decision Records)](./docs/adr)
- [Communications diary](./docs/communications-diary.md)
- [Developing notifyd](./docs/development.md)
  - [Developing the ruby client](./docs/ruby-client.md)
  - [How do we write code?](./docs/how-do-we-write-code.md)
  - [How do we test?](./docs/how-do-we-write-tests.md)
  - [Deploying notifyd](./docs/deployment.md)
- [Learning Resources](./docs/learning-resource.md)
- [Integrators guide - Mobile push notifications](./docs/integrators-guide-mobile-push-notifications.md)
- [How to track mobile push notifications?](./docs/how-to-track-mobile-push-notifications.md)
- Some issues that contain historical context for the project are labeled as such [`historical-context`](https://github.com/github/notifyd/issues?q=label%3Ahistorical-context) for future reference.

## Roadmaps

- [Q2 2023][q2-2023-roadmap]
- [Notifications Platform Board][project]

## Getting Help

Notifyd is owned by [@github/notifications](https://github.com/orgs/github/teams/notifications).
You can find us in slack in [#notifications-platform](https://github.slack.com/archives/C01H02W5GQK).

## Operations

### Dashboards and tools

| Name                                          | Type                   | Summary                                      |
| --------------------------------------------- | ---------------------- | -------------------------------------------- |
| [Notifyd APM Service Overview][apm-notifyd]   | APM                    | Distributed tracing and service dependencies |
| [Notifyd][dd-notifyd]                         | Metrics/monitors       | Main platform overview, mostly SLOs          |
| [Notifyd API][dd-notifyd-api]                 | Metrics/monitors       | Dashboard for the twirp API                  |
| [Notifyd Notify Worker][dd-notifyd-notify]    | Metrics/monitors       | Dashboard for the notify worker              |
| [Notifyd Mobile Push worker][dd-notifyd-push] | Metrics/monitors       | Dashboard for the mobile push worker         |
| [Notifyd Email worker][dd-notifyd-email]      | Metrics/monitors       | Dashboard for the email worker               |
| [Devportal dashboard][devportal]              | Deployment             | Deploys, environments and k8s resources      |
| [Professor X (database cluster) overview][db] | Database               | DB cluster management                        |
| [Splunk logs][logs]                           | Logging                | Application logs                             |
| [Splunk error logs][error-logs]               | Logging/errors         | Application logs (errors)                    |
| [Sentry][sentry-errors]                       | Exception reporting    | Unhandled exception reports                  |
| [Pyroscope profiling][pyroscope]              | Continuous profiling   | Application CPU/memory profiling             |

### Misc

- [Integrators requests][integrator-requests]

[logs]: https://splunk.githubapp.com/en-GB/app/gh_reference_app/search?q=search%20index%3Dnotifyd%20kube_namespace%3Dnotifyd-production
[error-logs]: https://splunk.githubapp.com/en-GB/app/gh_reference_app/search?q=search%20index%3Dnotifyd%20kube_namespace%3Dnotifyd-production%20deployed_to%3Dproduction&display.page.search.mode=verbose&dispatch.sample_ratio=1&earliest=-24h%40h&latest=now&display.prefs.events.count=50&sid=1622144191.9085_FE841334-378C-4E24-8F66-4197FEEBCFC9
[db]: https://professorx.githubapp.com/mysql/cluster/notifyd
[integrator-requests]: https://github.com/orgs/github/projects/2526
[project]: https://github.com/orgs/github/projects/3011
[q2-2023-roadmap]: https://github.com/orgs/github/projects/7635/views/1
[sentry-errors]: https://sentry.io/organizations/github/issues/?project=5962311&project=5962313
[devportal]: https://devportal.githubapp.com/devportal/apps/notifyd
[apm-notifyd]: https://app.datadoghq.com/apm/entity/service%3Anotifyd
[dd-notifyd]: https://app.datadoghq.com/dashboard/n77-d3g-dqh/notifyd
[dd-notifyd-api]: https://app.datadoghq.com/dashboard/c8y-x68-v7p/notifyd-api
[dd-notifyd-notify]: https://app.datadoghq.com/dashboard/dx4-knv-tfe/notifyd---notify-worker
[dd-notifyd-push]: https://app.datadoghq.com/dashboard/2bu-zrw-85q/notifyd---mobile-push-worker
[dd-notifyd-email]: https://app.datadoghq.com/dashboard/qzy-ek7-adh/notifyd-email-delivery-worker
[pyroscope]: https://pyroscope.githubapp.com
