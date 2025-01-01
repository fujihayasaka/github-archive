# Dependency Graph in GHES

Since ~ October 2020, Dependency Graph has been configured to use [nomad](https://www.nomadproject.io/) which runs dependency-graph with a docker container. The dependency-graph container is updated with a [GitHub action](https://github.com/github/dependency-graph-api/blob/master/.github/workflows/actions-cibuild.yml). Details on the contents of the container can be found in [github/dependency-graph-api](https://github.com/github/dependency-graph-api/tree/master/ghex-docker).

## Enabling Dependency Graph in GHES

You can follow the documentation [here](https://docs.github.com/en/enterprise-server@latest/admin/configuration/enabling-alerts-for-vulnerable-dependencies-on-github-enterprise-server#enabling-dependabot-alerts-for-vulnerable-dependencies-on-github-enterprise-server).

## Setting up your own Enterprise or Enterprise Org

If you don't have a (dotcom) org to GHConnect to, and you don't want (or can't) use `Avocado-Corp` you can use our shiny new team enterprise org, [Dependency Graph Enterprises](https://github.com/enterprises/dg-enterprises/). Ask a teammate for an invite. If you hit trouble, ask questions in `#connected-enterprise` Slack channel.

:exclamation: GitHub Connect is deprecating the ability to connect with an enterprise _organization_ and will only allow enterprises, so it will likely be more beneficial for you to use/create!

### Create an enterprise

- Get stafftools access and hop on over to the "Enterprise Accounts" [page](https://admin.github.com/stafftools/enterprises)
- Click on the "New Enterprise" button
  - Make sure to check off the "Staff owned?" box
  - Check off the "Advanced Security enabled" box and add several AS seats
  - Add some general seats to your enterprise
- Click save!

### Create an enterprise org

**From dotcom env, using your staff user login:**

- Browse to `https://admin.github.com/biztools/coupons/100Percent_Off_Forever_For_Stafftocat_Orgs`
  - Login to admin biztools if needed
  - Check coupon status: you might need to update the number of open subscriptions available or extend the coupon expiration date!
- Browse to `https://github.com/settings/organizations`
  - Create a new test org owned by your staff user
- Browse to `https://admin.github.com/biztools/coupons`
  - In the "Search For Coupons" box, enter `100Percent_Off_Forever_For_Stafftocat_Orgs`
  - On the Coupon page that comes up, type the name of your new test org and press the green "Apply to Account"
- Browse to `https://github.com/<YOUR_TEST_ORG_NAME>`
  - Browse to the settings page for your new test org
  - Browse to the Billing tab
  - Click "redeem coupon" and apply `100Percent_Off_Forever_For_Stafftocat_Orgs`
  - Back to Billing tab
  - Upgrade to the Enterprise plan
  - Optional (depends on your use case): enable Advanced Security for Unlimited Seats

## Setting up GH Connect

**From your GHE instance, using your `ghe-admin` login:**

- Create a test org on your **GHE instance** (give it a different name than your dotcom Enterprise-plan org)
- Browse to the **Enterprise Settings** page: `https://<BP_DEV_HOST>/enterprises/github/settings/dotcom_connection`
- Select "GitHub Connect" tab you should see your dotcom orgs listed:
  - _Ineligible orgs_ will be shown with an "Upgrade" button, meaning you will be charged if you upgrade them to Enterprise orgs
  - Your new test org should be shown with a "Connect" button - this means you're ready to go on the dotcom side
- Press your new (dotcom) test org's "Connect" button
- If successful, your GHE and dotcom test orgs are now linked
- **IMPORTANT!** Review the GH Connect feature enablement buttons:
  - This is on the **Enterprise Settings** page, **GH Connect** tab
  - Ensure all relevant Supply Chain product connections (Dependency Graph, Dependabot) are **ENABLED**

## Using Dependency Graph with `gheboot`

[`.gheboot`](https://github.com/github/ghe-boot) is a chatops utility you can use to build off a specific version of GHES, for example: `.gheboot 3.0.0`. This is useful for experimentation with GHES when you aren't actively needing to develop or make changes to GHES.

In`gheboot`, dependency graph is not enabled by default.

Login with the `ghe-admin` credentials, the chatops cmd will upon creating your `.gheboot` tell you to retrieve the password to use to login as the admin.

## Dependency Graph files in GHES

We own the following in `github.com/enterprise2`:

- The [dependency graph nomad job template files](https://github.com/github/enterprise2/blob/master/vm_files/etc/consul-templates/etc/nomad-jobs/dependency-graph-api): the dispatch, which handles migration, and our main serivce. The `00-dependency-graph-api-env.hcl.ctmpl` shares environment variables across the templates.
- The [dependency graph dispatch script](https://github.com/github/enterprise2/blob/master/vm_files/usr/local/bin/dependency-graph-api-env-dispatch) used in the [`ghe-run-migrations`](https://github.com/github/enterprise2/blob/master/vm_files/usr/local/share/enterprise/ghe-run-migrations#L268)
- Our testing scripts: `tests/test-dependency-graph-api-env-dispatch.sh`, `tests/test-vulnerability-alerting.sh`.

Additionally we have logic in:

- The `ghe-run-migration` script
- The `ghe-support-bundle` script on how our logs are exported
- The `ghe-prep-ghe` script to set a directory for the dispatch log which has the permissions set to be owned by our `dependency-graph-api` user in `vm_files/usr/local/share/enterprise/ghe-fix-permissions`

### How does GitHub.dependency_graph_enabled? actually get set in dotcom on GHES?

Assuming we have a value set in ghe-config (for example, `ghe-config app.dependency-graph.enabled true`), it can be a little opaque how that value actualy makes it into dotcom's `GitHub.dependency_graph_enabled?` method.

1. enterprise2 reads the setting from `github.conf` with its configapply subsystem. [enterprise2/vm_files/usr/local/share/enterprise/lib/configapply/dependency_graph.rb](https://github.com/github/enterprise2/blob/master/vm_files/usr/local/share/enterprise/lib/configapply/dependency_graph.rb#L28)
1. enterprise2 uses consul to transform a JSON representation of configapply to environment variables. [enterprise2/vm_files/etc/consul-templates/etc/nomad-jobs/github/00-env.hcl.ctmpl](https://github.com/github/enterprise2/blob/master/vm_files/etc/consul-templates/etc/nomad-jobs/github/00-env.hcl.ctmpl#L522)
   - An observant person would say "wait, why is there a `is_dependency_graph_enabled` property on the JSON?" There is [custom mapping logic](https://github.com/github/enterprise2/blob/e32a3d06fdd4fb3bce96891f826631781cde09c5/vm_files/usr/local/share/enterprise/lib/configapply/view_helpers.rb#L490) that prepends `is_` and drops `?` from method names in configapply while generating JSON.
1. gh/gh has [code called during startup](https://github.com/github/github/blob/master/lib/github/config/environments/enterprise.rb#L128) that automatically looks for all environment variables with a prefix of `ENTERPRISE_`, checks the GitHub module to see if it can "receive" set operations for those variable names, and then automatically sets. This is how GitHub.dependency_graph_enabled? is set, as opposed to any specific piece of code calling the property setting. Some developers prefer explicit reading of the environment variables to set configuration values, this could be an option for us going forward as well.

### How do jobs get enqueued from GHES dotcom to GHES dependency-graph-api?

GHES also uses [Aqueduct](https://github.com/github/dependency-graph-api/blob/master/docs/aqueduct.md). The Aqueduct worker in GHES is started [here](https://github.com/github/enterprise2/blob/master/vm_files/etc/consul-templates/etc/nomad-jobs/dependency-graph-api/dependency-graph-api.aqueduct-worker.hcl.ctmpl).

### Enterprise backport, release-branch update process

The Dependency Graph services are deployed in GHEX environments packaged as [this Docker image](https://github.com/github/dependency-graph-api/blob/master/ghex-docker/Dockerfile.ghex), based on a release candidate branch hosted on the `dependency-graph-api` repo named as `enterprise-X.Y-release` (example [here](https://github.com/github/dependency-graph-api/tree/enterprise-3.2-release)). A deployed instance of GHEX hosts `dependency-graph-api` services as containers using the Docker image built on the tip of the `enterprise-X.Y-release` branch. The `enterprise2` repo hosts the service mappings generated by the backport automation [here](https://github.com/github/enterprise2/blob/ad3c696a632aad36e2314e1467ebf48c0b7312f5/configuration.sh#L36) and [here](https://github.com/github/enterprise2/blob/ad3c696a632aad36e2314e1467ebf48c0b7312f5/docker-image-list-ghe#L26) and [here](https://github.com/github/enterprise2/blob/ad3c696a632aad36e2314e1467ebf48c0b7312f5/docker-image-list-ghe#L26).

To ship a `dependency-graph-api` code change to the appropriate `enterprise2` release branch, do the following:

- Merge the bugfix PR into default branch on `dependency-graph-api` repository
- Add the `enterprise-X.Y-backport` label to the merged PR (example [here](https://github.com/github/dependency-graph-api/pull/2144))
- Automation will pick up the label, open a new PR against the `dependency-graph-api`'s `enterprise-X.Y-release` branch, and _remove the label after_ (example [here](https://github.com/github/dependency-graph-api/pull/2153))
- Once ready and required approvals are gathered, merge the PR into DG's local `enterprise-X.Y-release` branch
- GHEX release team folks will run `.ghe sha1-sync enterprise-X.Y-release dependency-graph-api` chatop to backport the change from our release branch over to the `enterprise2`'s release branch of the same name

The full documentation can be found [here](https://github.com/github/enterprise-releases/blob/master/docs/backport-an-existing-pr.md).

If you need to confirm the status of a backport you can use `.ghe unmerged-backports`.

**Manual Backport Testing**
Upon the backport being merged in, such as this [example backport PR to enterprise 2.21.19 patch](https://github.com/github/github/pull/175502), testing should be confirmed before the final enterprise patch is released. You can build and test off the patch with:

```
.gheboot <QA issue number>   # Look in https://github.com/github/enterprise-releases/issues for the relevant QA issue for your release
```

## Development in GHES

Development in GHES can be done with a `.bp-dev` instance. The workflow for building a `.bp-dev` is as such:

```
.bp-dev launch ghe    # To create an instance
.bp-dev list ghe    # To see your instances
.bp-dev destroy ghe <name> # To destroy your instance
```

The [dependency graph api docs](https://github.com/github/dependency-graph-api/#running-via-bp-dev-ghe-development-environment) discusses how to setup dependency graph.

For more detailed information on getting started with `.bp-dev` you can reference the [GHES-Infrastructure Docs](*https://github.com/github/ghes-infrastructure/blob/main/docs/getting-started/using-single-tenant-ghe-developer-instances.md#quick-start).

Need help? Slack channel `#ghes` can assist.

## Testing new changes in GHES

Pro-tip: Highly recommend following the instructions [here](https://github.com/github/ghes/blob/main/docs/getting-started/using-single-tenant-ghe-developer-instances.md#vscode-integration) if you plan to do a good amount of work is VSCode. It's worth the amount of time it'll take to set things up.

From there you'll be able to launch a workspace using `code --remote ssh-remote+FQDN /workspace/enterprise2` and be ready to roll!

### enterprise2

Simply take the most recent `enterprise2` SHA in your branch and plug it into the launch chatop.

```
.bp-dev launch ghe --sha 5fcfd3df2e6ee2d754e8ca262597191d5830aa2d --enable_ui
```

Follow regular boot instructions after that.

Tip: interested in making changes to the Management Console? [The code](https://github.com/github/enterprise2/tree/master/enterprise-manage) for it actually lives in `github/enterprise2`, and not `github/github`!

### dependency-graph-api

Once you set up your bp-dev instance, you'll be able to run `script/update-service.rb` to obtain the correct docker image links that have your changes.

**Note!** This should be done before you start down the path of running `./chroot-build.sh` and other build steps.

To ensure you have a docker image for your changes, navigate through the following:

1. Go to your PR and ensure CI has built.
1. Navigate to the `Build Container` action and click on `Details`.
1. Click on `Push Results to GPR if a push to master`.

You should see a `docker_image_url` link like this:

```
docker_image_url: dependency-graph-api=ghcr.io/github/dependency-graph-api/dependency-graph-api:<SHA HERE 986215b90e814dee943674213c059992bdc52b9f>@sha256:3421a2467eed754b1a83ec626dbcca31ad31aa67b3082a4a45c21c3caac51a7e
```

The location of the SHA is in the tag. You can then run the following in your bp-dev shell to get the desired SHA synced.

```
script/update-service.rb dependency-graph-api <your dg-api SHA>
```

From there, follow the [regular build scripts process](https://github.com/github/dependency-graph-api/#running-via-bp-dev-ghe-development-environment).

### dotcom

Dotcom testing is similar to dependency-graph-api's but is a little more complicated.

1. Navigate to the [`Publish GHES docker containers`](https://github.com/github/github/actions/workflows/build_enterprise_containers.yaml) action.
1. You'll need to start your own workflow run. Click on the `run workflow` dropdown and select your branch.
1. The dropdown can be a bit finicky. Click the branch selection to ensure your branch has a check next to it.
1. Start the workflow run. Ensure the commit under `Triggered` is from your branch.
1. Once the build is done, you should be able to use commit in the last step to test your changes.

```
script/update-service.rb github <some dotcom SHA>
```

From there, follow the [regular build scripts process](https://github.com/github/dependency-graph-api/#running-via-bp-dev-ghe-development-environment).

## Helpful Nomad Commands

The following are helpful `nomad` commands:

- `nomad monitor` to observe all output of nomad job activity
- `nomad status` to observe the status of any job(s)
- `nomad exec -job dependency-graph-api-service /bin/bash` to access shell inside dg-api service container

The nomad job logs are aggregated with `journalctl`, using `journalctl -ft dependency-graph-api` allows you to tail the logs for the nomad dependency-graph-api job.

## Testing

There are useful utilities defined in the `test/lib.sh` - such as `ssh_cmd` to connect to the appliance - and `test/mountebank.sh` scripts in `github/enterprise2`.

Dependency graph has tests in the following:

- `tests/test-dependency-graph-api-env-dispatch.sh`
- `tests/test-vulnerability-alerting.sh`

Individual tests can be run via `./choot-runtest.sh test/test-<name>.sh` on a `.bp-dev` instance.

### Using Mountebank

[Mountebank](http://www.mbtest.org/docs/commandLine#start) is an open-source cross-platform testing tool which allows you to mock out a service with `imposters` fixtures. For an example of how to use reference `tests/test-vulnerability-alerting.sh` to the `imposter` fixture used to generate vulnerability data for the tests. The docker container that is spun up is named `montebank:latest`.

## Support

We are responsible for triaging any GHES issues related to dependency graph. Below are some helpful pieces of information to help you get started.

### Using Support Bundle Logs

The dependency graph logs can be exported with the [`ghe-support-bundle`](https://github.com/github/enterprise2/blob/master/vm_files/usr/local/bin/ghe-support-bundle) script (see: `ghe_services` for list of services included), to create one:

- `./chroot-ssh.sh` to log into the appliance
- `ghe-support-bundle -u`
- You can either access via <https://enterprise-bundles.github.com/> or `ssh -t esbtools-shell-2e30973.private-us-east-1.github.net "/home/esbtools/bin/launch [<upload_id_number>]`

**Where our service output is in the support bundle**

- The `dependency-graph-api-dispatch` nomad job handling the migration will be at `/dependency-graph-api-dispatch-logs`.
- All `nomad-jobs` are output to `/system-logs/nomad-jobs/` where the following is available:
  - `<nomad-job-name>.json` and `<nomad-job-name>[0].json` capturing the output on if the nomad job ran, failed, etc.
  - `alloc/<unique-identifier-for-the-allocation>/logs/dependency-graph-api-service.stdout.0` and `alloc/<unique-identifier-for-the-allocation>/logs/dependency-graph-api-service.stderr.0`, `dependency-graph-api-service` is [configured to log to](https://github.com/github/enterprise2/blob/master/vm_files/etc/consul-templates/etc/nomad-jobs/dependency-graph-api/00-dependency-graph-api-env.hcl.ctmpl#L12) `STDOUT`

### Useful logs

Here's a quick list of logs that may be useful for you if debugging dependency graph:

#### On the appliance

- `journalctl -ft dependency-graph-api` for reading nomad logs for our dependency-graph-api job
- `/data/user/common/ghe-config.log` for reading the output of the `./chroot-configuration.sh` script

#### On bp-dev

- `./chroot-configure.sh` logs are output to `/data/user/common/ghe-config.log`, including the output for the migration
- `nomad monitor` will show locations of the nomad alloc logs too, for example:

```
2021-03-11T17:44:32.880Z [INFO]  client.alloc_runner.task_runner.task_hook.logmon.nomad: opening fifo: alloc_id=82ec4165-e68c-bd71-f2b7-cff1d6e2083f task=dependency-graph-api-dispatch @module=logmon path=/data/user/nomad/alloc/82ec4165-e68c-bd71-f2b7-cff1d6e2083f/alloc/logs/.dependency-graph-api-dispatch.stdout.fifo timestamp=2021-03-11T17:44:32.880Z
```
