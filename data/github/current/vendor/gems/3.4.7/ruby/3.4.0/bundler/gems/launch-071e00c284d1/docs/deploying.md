# Deploying

Launch is a Moda app and follows a similar process as [Deploying Dotcom](https://thehub.github.com/engineering/development-and-ops/deployment/deploying-dotcom/).


Anyone with Heaven entitlements can deploy `launch`, but you need to have `write` permissions on https://www.github.com/github/launch in order to merge your PR afterwards.

## Environments

Launch has three deployment environments - `lab`, `prod/canary`, and `prod`

The Lab environment runs `.github/workflows-lab` workflows and communicates with Actions Service Ring 0. (In some cases now it is instead communicating with the run-service, see [four-nines](./four-nines.md) for more details).

The `prod/canary` environment is a small portion of the traffic sent to production.
When doing a `prod` deployment, changes are automatically first deployed to the `prod/canary` environment.

See [Environments](./environments.md) for more information about the different Launch deployment environments.

## Where to Deploy

For changes that are "No risk" or "Low risk", such as documentation and test changes, it's sufficient to only to the `prod` environment.

For all other changes, you should deploy to `lab` before proceeding to `prod`.


| Risk Level        | Recommended Deployment Environments |
| ----------------- | ----------------------------------- |
| None, Low         | `prod`                              |
| Medium, High      | `lab` -> `prod`                     |

## Monitoring Deployments

During deployments, check the linked Sentry release for any errors and monitor the Datadog deployment dashboard.
If you see anything suspicious, feel free to reach out in [`#launch`](https://github-grid.enterprise.slack.com/archives/C7MHXGDEW) or rollback (`.deploy launch`).


The [Deployment Confidence dashboard](https://app.datadoghq.com/dashboard/8nz-4rv-6gf/github-actions-deployment-confidence) can be filtered to a specific deployment environment - the link given by Hubot should already have the necessary environment filters.

[Splunk](https://splunk.githubapp.com/) can also be filtered by `launch_env` (`lab` or `production`) and the deployment Launch ref with `release`.

```
index=prod-launch launch_env=lab release=SHA
```

## Deployment Steps

*As of May 11th, 2022 Launch is using the merge queue for deployments*
Manual deploys are allowed, but you'll need to go through the merge queue before merging.
To queue your pull request to deploy, use `.qmtd https://github.com/github/launch/pull/1` or use the pull request merge box UI.
You can use `--jump` option or the equivalent merge box option to skip ahead of other pull requests in the queue.

Launch is currently configured to only use 1 pull request per merge group, so the solo option shouldn't be necessary.

Once your PR is up to deploy, it will automatically be deployed to canary and production via a [deployment pipeline](https://heaven.githubapp.com/apps/launch/pipelines/production_rollout)
If there are issues during the deploy, you can pause or cancel the pipeline.

To check the merge queue, visit https://github.com/github/launch/queue or use `.queue for launch`

### Slack Deployment Commands

In [#actions-launch-ops](https://github.slack.com/archives/C7S87E2RW):

1. `.wcid launch` - "where can I deploy launch", tells you the current deployment status
1. `.deploy https://github.com/github/launch/pull/1 to lab` - deploy to our Lab environment

    - Successful lab deploys should trigger a run of the lab test suite in [`actions/canary`](https://github.com/actions/canary). You'll see a message in the deployment channel for Launch.
    - https://github.com/actions/canary has a set of [Lab workflows](https://github.com/actions/canary/tree/main/.github/workflows-lab) that can be run to validate any changes, see [lab/RUNS.md](https://github.com/actions/canary/blob/main/lab/RUNS.md)

1. `.deploy launch to lab` - deploy the `master` branch of Launch to the `lab` enviroment. This indicates that you are done testing and unlocks the `lab` environment for other deployments.
1. `.qmtd https://github.com/github/launch/pull/1` - deploy to prod

## Canary deploys

One thing to note about canary deploys is that the request routing to instances of Launch processes running the canary code is random. If you need deterministic routing to your code to vet it, you should use a lab deployment as mentioned in the previous section. The canary deployment is only a mechanism to see how your code responds to small amounts of production traffic.

## Skipping the merge queue

If there are issues deploying or merging Launch changes due to the merge queue, you can disable the merge queue branch protection rule for `master`

1. Navigate to https://github.com/github/launch/settings/branches and edit the default branch protection rule
2. Uncheck "Require merge queue" and click save
