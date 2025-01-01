# migrations-vnext

A new approach to migrating customer data.

## Development

Currently, the best way to see the service in action is by importing an existing org/repo from
a GHES instance. If you would like to only test archive migrations, you can skip privisioning
a GHES instance.

### GHES instance

Create a GHES instance with `.gheboot 3.15 --ttl 14`.

Make a note of the GHES instance URL (https://xyz), we'll refer to it as `GHES_URL`.

Create a PAT with repository permissions, we'll refer to it as `GHES_TOKEN`.

Create an org/repo, `acme/smc` is the default org/repo the scripts are expecting but it
may be changed and set accordingly further in the process..

Create some resources to be migrated. You can start with some simple ones, such as issues.

### github/github

Create a `gh/gh` Codespace and clone this repo in `/workspaces/migrations-vnext`.

Start github and other services:

```shell
script/mvnd-enabled-server
```

### Testing a live migration from GHES

SSH into the created codespace with:

```bash
gh codespace ssh -c your-code-space-name -- -A
```

The following steps work better if you are SSH'ing using `iTerm` on your local machine. If you aren't,
run the following:

```
export ITERM_DISABLED="true"
```

Go into the `/workspaces/migrations-vnext` and run:

```bash
GHES_URL="your GHES_URL" GHES_TOKEN="your GHES_TOKEN" script/setup-tmux
```

The command above should prepare your environment, and open a  `tmux` session on `iTerm` where each pane
contains each one of the services ELM needs to run.

The last pane contains the command to start the repo migration. You just need to press return to kick it off.

You should see the resources being migrated from GHES into http://avocado-gmbh.ghe.localhost

Live updates for resources that are currently supported should also work out of the box.

If you want to start over a migration, you can do the following:

1. Delete the repo from the target instance
2. Stop the docker process (or all the processes and run script/setup-tmux again)
3. Run `script/dev-setup/prepare-for-deleted-repo`
4. Run the migrate-repo script again

##### Troubleshooting issues with `gh/gh`
When following the subsequent sections for development testing you may cause unexpected issues and wish to reset the state.
```
# stop script/server
bin/rails db:reset # wipes the database completely, useful for starting again from scratch.
bin/elastomer reset # recreates elasticsearch indexes, should be run after db:reset, can cause pages to not load properly (or at all) if indexes don't exist.
```

### Testing archive migrations
The following steps should happen in this repo.

Start docker compose to bring up Kafka, Redis, etc.

```shell
script/docker
```

Start the worker:

```shell
script/mvnworker
# The following can be set to run with a mock import client instead.
# DUMMY_IMPORTER=true script/mvnworker
```

Start a DAG worker:

```shell
script/mvndagworker
```

### Testing acme archive

This archive is included in this repository as it is rather small. It does not include every possible case but can be used to get some signal.

Preseed data for `acme-widget`:

```shell
script/preseed-acme
```

Run `archiveloader` to load the fixtures out-of-order:

```bash
script/archiveloader
```

If you want to test PRs and other resources that require git data, once the repo is created, you can run the following command to push
git data:

```bash
script/acme-push
```

### Testing acme archive in Proxima mode

Run gh/gh in proxima mode in your codespaces:

```shell
script/mvnd-enabled-server
```
If you need to log in to the UI navigate to `http://avocado-gmbh.ghe.localhost` to sign in.


Preseed data for `acme-widget`:

```shell
script/preseed-acme-proxima
```

Run `archiveloader` with `default-user-id` set to `25` (`monalisa_avo`)

```shell
ARCHIVE_ROOT=integration/fixtures/acme-widgets-proxima script/archiveloader --allowed-resources=organization,user,repository,protected_branch,issue,issue_comment,issue_event,milestone,pull_request,project,label,commit_comment,noop --default-user-id=25
```

Note: attachments and releases are not working in Proxima mode so they are not included here.

Run `mvnworker` with `enterprise-id` set to `4` (`avocado-gmbh`):

```shell
BASE_URL=http://api.avocado-gmbh.ghe.localhost/internal script/mvnworker --enterprise-id=4
```

The rest is the same.

### Testing docs-internal

Get the `docs-internal` metadata archive in your Codespace and uncompress it.

Follow the steps above to use out-of-order loading but point it to the `docs-internal` archive:

```bash
script/preseed-docs-internal
```

```shell
ARCHIVE_ROOT=$docs-internal-uncompressed-path script/archiveloader
```

Currently, there are two issues you might run into:

- `gh/gh` might stop due to issues with `authd`. Restart `gh/gh` and any the `mvnworker` process.
- `mvndagworker` might fail to write to Kafka (we are currently working on improving this). Restart it.

### Testing octoshift

Get the `octoshift` archive in your Codespace and uncompress it in `/workspaces/octoshift`.

Follow the steps above to use out-of-order loading but point it to the `octoshift` archive:

```bash
script/preseed-octoshift
```

`attachments` don't work on the octoshift repo yet, so please use the following command:

```shell
ARCHIVE_ROOT=/workspaces/octoshift ALLOWED_RESOURCES=organization,user,repository,protected_branch,issue,issue_comment,issue_event,milestone,pull_request,project,label,commit_comment,release,noop script/archiveloader
```

If you want to test PRs and other resources that require git data, once the repo is created, you can run the following command to push
git data:

```bash
script/octoshift-push
```

### Test

```shell
make test
```

### VSCode Debugging
VSCode launch configurations are included to allow for easier debugging. For
these to work, run `script/vscode-env` after starting the docker services. This
script will populate the necessary environment variables in `script/env.out`,
which the launch configurations read from. After that, you can launch the
program you'd like to debug and set breakpoints as needed.

## In-order vs. Out-of-order

We have experimented with two ways to load resources from the archive.

In general, we try to model the dependencies between resources in a DAG. This DAG represents
the resources that need to be migrated along with the dependencies between them. For example,
a repository depends on an organization, and an issue depends on a repository and an author.

To make sure that we don't migrate resources before their dependencies, we need to traverse the
DAG in a way that respects the dependencies.

We have settled on using the out-of-order approach described above, although we started
with the in-order approach.

### In-order

The in-order approach means that, as we now the shape of the DAG, our code explicitly loads
the resources in the order that respects the dependencies.

This works well, and it could reasonably get us far if we were to load resources
from an archive.

## Out-of-order

The out-of-order approach is an experiment to answer the question _"what if we wanted to stream the resources"_
one-by-one, or in batches, where the order of the resources is not guaranteed to respect the dependencies.

The way we are approaching this is by dynamically building the DAG as we see the resources. The current
implementation persists the DAG in Redis–we could use other store though–which allows us to use
the DAG in a distributed way.

When a new resource is received, we do the following:

- Persist the resource payload in Azure Blob Store
- Add the resource ID and its dependencies to the DAG, but we don't add the resource itself.
- The DAG is evaluated to see if any nodes have their dependencies satisfied. If so, we add the node to eligible nodes list.
- Iterate over the eligible nodes list and:
   - The resource is loaded from Azure Blob Store
   - It is written to Kafka for processing
   - It is marked as processed in the DAG, and this triggers the evaluation of the DAG to see if any other nodes can be processed.

This out-of-order processing has already surfaced issues with certain resources where the current import API
falls short. E.g: milestones, or to be more precise, assigning issues to milestones is not possible today with the current
import API and an out-of-order approach.

## Additional Documentation
- [Development](./docs/development.md)

