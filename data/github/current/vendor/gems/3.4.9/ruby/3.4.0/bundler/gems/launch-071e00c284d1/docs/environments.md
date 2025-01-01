# Launch Environments

- `lab`: A relatively safe environment to validate risky changes.
- `prod/canary`: Testing in production with a small amount of traffic.
- `prod`: It's prod!

In almost every case, `lab` and `prod`/`prod/canary` use the same endpoints and services. However, there are a few notable differences called out below. In the chart below, a `-` indicates that there is no difference between the production environment.

|                         | `lab`                                                                | `prod/canary` | `prod`                                            |
|-------------------------|----------------------------------------------------------------------|---------------|---------------------------------------------------|
| aqueduct endpoint       | -                                                                    | -             | production                                        |
| aqueduct queues         | `webhooks-lab`, `scheduled_builds-lab`, `dynamic_builds-lab`         | -             | `webhooks`, `scheduled_builds`, `dynamic_builds`  |
| HTTP(S) Proxy           | -                                                                    | -             | -                                                 |
| API Host                | -                                                                    | -             | -                                                 |
| External API Host       | -                                                                    | -             | -                                                 |
| External GitHub Host    | -                                                                    | -             | -                                                 |
| Launch MySQL            | -                                                                    | -             | -                                                 |
| Payloads MySQL          | -                                                                    | -             | -                                                 |
| Hydro Endpoint          | -                                                                    | -             | -                                                 |
| Receiver URL            | `launch-receiver-lab`                                                | -             | `launch-receiver`                                 |
| GitHub Twirp Address    | -                                                                    | -             | -                                                 |
| AZP Org Create Base URL | Same as prod, but pinned to `/serviceDeployments/pipelinesghubeus20` | -             | `https://pipelines.actions.githubusercontent.com` |
| Spokesd Endpoint        | staging                                                              | -             | production                                        |
| Authzd Endpoint         | -                                                                    | -             | production                                        |

## Running workflows on Lab

A few special steps need to happen in order for a workflow to be handled by **launch** `lab` environments.

1. Ensure the [`launch_lab`][lab-feature-flag] is enabled for the repository or organization to ensure the Actions Lab GitHub App is installed (see https://github.com/github/github/pull/327739#discussion_r1635541535)
1. Enable the [`launch_lab`][lab-feature-flag] feature flag for the *repository* [so that it is not skipped](https://github.com/github/launch/blob/1e082e7b17afb22ac616d691422feeb6c386f3ea/services/deploy/workflowinvoker/workflowinvoker.go#L528-L534), except for repos in the [lab enabled orgs][lab-enabled-orgs] `actions-sauron`, `bbq-beets`, `bbq-beets-four-nines`, and `actions-canary-dependabot`.
2. The workflow [must be in the lab workflow directory](https://github.com/github/launch/blob/14ce7e8d48e6bc0046dcd952378379dc9d5ca085/flow/flowfile/paths.go#L41-L47) `.github/workflows-lab`.

[lab-feature-flag]: https://devportal.githubapp.com/feature-flags/launch_lab/targeting-rules?stamp=dotcom
[lab-enabled-orgs]: https://github.com/github/launch/blob/1e082e7b17afb22ac616d691422feeb6c386f3ea/clients/github/getworkflowinvocationdata.go#L21-L31

## Running on Actions Ring 0
 - Actions Service and other services in `AzDevNext` use ring 0 deployments to ensure that changes first rollout to internal customers and internal test accounts.
 - If you enabled Actions on a repository via **launch** `lab` it will belong to `ghub-eus2-0`, a ring 0 scale unit. Repositories that are not in a ring 0 scale unit can be transferred there, see the docs for this [here](https://github.com/github/c2c-actions/blob/main/ado-wiki/Standards,-Practices-and-Tools/Fundamental-Tools-and-Infrastructure/AME/Tenant-Transfer-Process.md).
 - A repository can have two tenants, and therfore belong to up to two scale units, one for prod and one for Lab.

## What about Aqueduct queues?
### Webhooks Queue

For a nice write up on event subscription, see @joshmgross's [spike](https://github.com/github/c2c-actions-experience/issues/4455#issuecomment-776861326). Launch will receive events from both workflow directories (`workflows` and `workflows-lab`), but will skip the aqueduct job if the workflow path doesn't match the one configured for the Launch environment.

This means that a production and lab instance would receive an aqueduct job, but only one or the other will process it, since the workflow path convention is mutually exclusive.

### Dynamic Queue

Queueing a dynamic run is done by calling the Dynamic Run Twirp endpoint. Currently, only the production Launch client calls the Dynamic Run Twirp call.

### Scheduled Queue

The Lab instance of Launch is configured to use a different queue than the production instance. When scheduled workflows are queued, [they are sent to the configured queue](https://github.com/github/launch/blob/4d4694564758f7b00be654fae2631e6fa3552b1b/services/deploy/scheduled/worker.go#L266-L267).

## Can a dotcom review lab send workflows to Launch?

It's currently not possible, because `github/github` sends aqueuduct jobs to staging when in `lab` or `review-lab`. However, regardless of environment, Launch only listens to the Aqueduct production endpoint.