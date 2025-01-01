# Launch in Four Nines

Launch is a key part of the 4 nines architecture. It is responsible for listening to repository webhooks, deciding when a workflow needs to be run, parsing the workflow into a plan, and then queueing the plan with `actions-run-service`.

Related components:

- Parsing the workflow into a plan is done with the [`actions-workflow-parser`](https://github.com/github/actions-workflow-parser) package, which itself uses the [`actions-expressions`](https://github.com/github/actions-expressions) package for parsing and evaluating expressions.
- Posting to `actions-run-service` is done with the API defined in the [`github/actions-proto`](https://github.com/github/actions-proto/blob/main/proto/run-service/api/twirp/v1/run_service.proto) definitions.

## Lab configuration

The `lab` configuration of `launch` is configured to send a workflow run to `actions-run-service` instead of to `actions-service`.

If the repository is not in `bbq-beets-four-nines`, the _repository_ must also be flagged into the `actions_launch_run_service` feature flag - You can manage this [here](https://devportal.githubapp.com/feature-flags/actions_launch_run_service/overview)

See [Running Workflows on Lab](./environments.md#running-workflows-on-lab) for information on enabling lab workflows.

## Logs in Splunk or Kusto

Logs from this environment have `launch_env=lab` tagged on them. When queuing a build to `run-service`, we output `plan queued in run service`.

## Triggering Dependabot Dynamic Workflows

See our [Dynamic Workflows docs](./dynamic-workflows.md) for examples of how to trigger a dynamic workflow in a Codespace and in Lab. For Dependabot specifically, we have `script/actions/queue-dependabot-dynamic-run.rb --nwo github/private-server --ref d91a71c047793598c3bd4e75e730c8c84b085ac2 --runson self-hosted`. For lab, those docs describe using a production Rails console to run a lab dynamic workflow. You need to replace the generic workflow contents in the `workflow` variable shown there with [this Dependabot workflow](https://github.com/github/github/blob/master/script/actions/queue-dependabot-dynamic-run.rb#L38) which is functionally equivalent to the one Dependabot uses.

## Triggering any workflow to route to 4 nines

As a way to select specific workflows instead of entire repositories, if a workflow starts with this comment: `# run-in-four-nines` it will be routed through to the new 4-nines architecture. The following must also be true:
- the workflow is a lab workflow (will work in production soon, but not yet)
- the workflow repo or org has the [`actions_allow_run_service_annotation` feature flag](https://admin.github.com/devtools/feature_flags/actions_allow_run_service_annotation) enabled (all lab enabled orgs will be flagged in)

