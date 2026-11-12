# GitHub Copilot Coding Agent (sweagentd)

> **Note:** You might see this project referred to by the name `sweagentd`, "GitHub Copilot Developer (CPD)", "Project Padawan", or "Copilot dev mode"

GitHub Copilot coding agent can be assigned issues, produce PRs, respond to feedback or build failures, and collaborate with engineering teams on software engineering projects.

Read the original whitepaper: [Autonomous Software Engineering AI Agents.docx](https://microsoft-my.sharepoint.com/:w:/p/lukehoban/EXa5UXaWosBMsrmK97fK4vMBVr7qroJ_jtU7Iej8f1cIRg?e=jno0dM)

## Want to try it out?

The agent is now in Public Preview! Check out our [docs](https://docs.github.com/en/copilot/using-github-copilot/coding-agent/about-assigning-tasks-to-copilot) to get started.

Head to `#coding-agent-dogfood` in Slack, and share your feedback! ❤️👀

## Staging environment

### Deployment

At this moment in time, we operate out of the [#copilot-extensibility-ops](https://github-grid.enterprise.slack.com/archives/C06C2V2EE5T) channel for running these commands. See [how to deploy an app](https://thehub.github.com/epd/engineering/devops/deployment/how-to-deploy-an-app/#deploy-the-app) for more info about how GitHub does deployments.

1. Get a PR approval (do not merge, only approval is needed)
1. `.wcid sweagentd` (optional) you can check status of environments by running
1. `.deploy <PR url> to staging` (you may see a locked env here, that's ok and you can ping whoever has it locked to ask for availability info)
1. `.unlock sweagentd in staging` when you're finished. Important to release it back to others.
1. `.deploy sweagentd to staging` (optional) restores staging back to latest main. This happens automatically every time we deploy main, too.

We have three staging environments, `staging`, `staging-jedi-knight`, and `staging-sith-lord`. Pick any open one and deploy to it, replacing `staging` in the above commands with the appropriate environment name!

### Testing

Use one of the blessed staging repositories, one exists for each staging environment:
* staging: ([github/padawan-testing-staging](https://github.com/github/padawan-testing-staging))
* staging-sith-lord: ([github/padawan-testing-staging-sith-lord](https://github.com/github/padawan-testing-staging-sith-lord))
* staging-jedi-knight: ([github/padawan-testing-staging-jedi-knight](https://github.com/github/padawan-testing-staging-jedi-knight))

### Notes

* The agents panel currently doesn't route to swe staging environments! Don't count on jobs initiated from there to route as expected.
* Issues assignment is moving to a model where they manually kick off jobs instead of using hydro events. They have their own routing to staging environments that should be handled with [this code](https://github.com/github/github/pull/399323).

<details>
     <summary>You can route other repos / users to staging environments, but it is complicated:</summary>

In order to get specific Copilot coding agent jobs to route to different staging environments, you can opt in your owner/repo/user using one of the following feature flags:

* staging: [sweagentd_route_user_or_repo_to_staging feature flag](https://devportal.githubapp.com/feature-flags/sweagentd_route_user_or_repo_to_staging/targeting-rules/actors-view?stamp=dotcom)
* staging-jedi-knight: [sweagentd_route_user_or_repo_to_staging_jedi_knight feature flag](https://devportal.githubapp.com/feature-flags/sweagentd_route_user_or_repo_to_staging_jedi_knight/targeting-rules/actors-view?stamp=dotcom)
* staging-sith-lord: [sweagentd_route_user_or_repo_to_staging_sith_lord feature flag](https://devportal.githubapp.com/feature-flags/sweagentd_route_user_or_repo_to_staging_sith_lord/targeting-rules/actors-view?stamp=dotcom)

Hydro events that trigger the runtime arrive with your user as the actor, and that means that event will be fully processed in the staging environment. **However**, certain events (like ComputeUsage) **do not contain your user as the actor** , meaning that the feature flag enablement can be skipped for those specific events. If you want staging to process these events, you should enable the feature flag on a repository that can safely be opted into staging routing. **Do not** enable this feature flag on a repository that might see non-development traffic, since you will impact all repository users if you do!

**Make sure to remove your user from the feature flag when you are done**, or you may find that you are confused about why you are seeing strange behavior as others may be testing changes in staging.

One easy trick could be to just consistently use a single test repository that is permanently opted into the feature flag, which will guarantee that all events are processed in the staging environment, and you won't need to keep track of toggling your user.
</details>

### What if the environment is in use?

Just DM the person who has it locked. If there isn't an explicit lock reason and the person is not responding, there's a good chance that they forgot to unlock the deployment. If you DM them and they're not available and it's been an hour or two since they deployed to staging, you should be OK to manually unlock and use the environment.

## Testing the Job API

The `sweagentd` service provides a [Job API](./docs/adr/0001-create-job-api.md) that allows you to kick off, get status on, and cancel coding agent jobs. Since this can have unique challenges, be sure you run a test of the API before deploying your changes.

To make this easy, the `script/job-api` script is simple wrapper around the needed curl calls. You can use it against a `--local` environment for testing in a codespace, the `--staging` environment, or even triage problems in `--production`.

For example, this will create a simple new job locally in a codespace:

```bash
script/job-api --local new github/private-server '{"problem_statement":"Improve the README."}'
```

More examples and usage can be found by running:

```bash
script/job-api --help
```

You can copy this script locally for use as well. See `--help` for details on expected environment variables.

## Working with the Runtime Submodule

The `runtime/` directory is a git submodule pointing to the [copilot-agent-runtime](https://github.com/github/copilot-agent-runtime) repository. This repository contains the runtime implementation and benchmarks.

### Initial Setup

When cloning this repository for the first time, initialize the submodule:

```bash
git clone git@github.com:github/sweagentd.git
cd sweagentd
git submodule update --init --recursive
```

### Common Submodule Operations

**Update submodule to latest commit on main:**
```bash
cd runtime
git checkout main
git pull
cd ..
git add runtime
git commit -m "Update runtime submodule to latest"
```

**Check current submodule commit:**
```bash
git submodule status
```

**Make changes in the runtime submodule:**
```bash
cd runtime
# Make your changes, commit them
git checkout -b my-feature-branch
# ... make changes ...
git commit -m "My changes"
git push origin my-feature-branch
# Create PR in copilot-agent-runtime repo
cd ..
# After PR is merged, update the submodule reference
cd runtime
git checkout main
git pull
cd ..
git add runtime
git commit -m "Update runtime to include my-feature"
```

**Reset submodule to the committed version:**
```bash
git submodule update --init --recursive
```

### Important Notes

- The `runtime/` directory is a separate git repository. Changes made inside `runtime/` must be committed in the runtime repository first.
- To update the submodule reference in sweagentd, you need to commit the new submodule commit hash in the parent repository.
- If you see `runtime (new commits)` in `git status`, it means the submodule has new commits that aren't yet committed to the parent repository.

## Want to start contributing to this project?

Jump to one of these docs:

- **sweagentd**: [docs/service-dev-setup-with-github.md](docs/service-dev-setup-with-github.md)
- **Runtime**: [runtime/docs/runtime-dev-setup.md](runtime/docs/runtime-dev-setup.md)
- **CLI**: [runtime/docs/cli/dev-setup.md](runtime/docs/cli/dev-setup.md)

## Architecture

You can read more about the architecture of Project Padawan in [docs/architecture.md](docs/architecture.md).

## Where can you reach us? :copilot:
- Team channel: `#coding-agent-team`
- General channel: `#coding-agent`
- Dogfood channel: `#coding-agent-dogfood`

## What are we up to? 
Check out our weekly team demos [here](https://www.loom.com/spaces/Copilot-Coding-Agent-38857939/folders/Coding-Agent-team-demos-f9f61f478d1a4403b1880d7ec00fe3ed), or see the pinned issue. 
