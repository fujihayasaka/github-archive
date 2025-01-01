# Local development

Getting github.localhost running with pushes triggering workflows etc:

## First time setup

These will need running again if you wipe your local `github/github` database:

- In `github/launch` run `script/setup`. This creates the "Launch Dev" GitHub app and updates the database schema if necessary.
- In `github/github` run `bin/seed actions` (recommended). This accelerates testing by creating the `github/hub` repo, adding several workflows and 20 runs for UI testing and possibly setting some preview feature flags. ([code](https://github.com/github/github/blob/master/script/seeds/runners/actions.rb))

## End-to-end Development Environments

There are three ways of setting up connectivity to the Actions Service, ordered by ease of use:

### Actions on Codespaces - RECOMMENDED

Run Actions in a full E2E environment via Codespaces, see [Actions Development](https://github.com/github/c2c-actions/blob/main/docs/actions-development.md)

### Actions BP-Dev

Spin up an E2E Actions dev environment with bp-dev, see [Hosted End to End Actions Development Environment - bp-dev](https://github.com/github/c2c-actions/blob/master/docs/actions-e2e-bp-dev.md).

### Local Actions Service

> This is not recommended but can be used as a fallback if Codespaces or `bp-dev` doesn't work for a specific use case.

You need to get the development key for your local [Actions Service](https://thehub.github.com/engineering/development-and-ops/actions/actions-dev-environment/#actions-services):

- `git clone https://github.com/github/c2c-actions-service.git` if you don't have it already
- in `github/c2c-actions-service` run `cd util/pipecli`
- `npm install`
- `npm run-script pipe retrieveSPPrivateKey --targetEnv devfabric`
- Do the Microsoft login dance (open [a browser window](https://microsoft.com/devicelogin) and enter the token shown at the CLI)
- `mv dreamlifterSP.devfabric.private.pem ~/{your-launch-path}/tmp/`

For testing scenarios where [Actions Service uses a shared hmac secret to sign requests to Launch](https://github.com/github/c2c-actions-service/blob/master/docs/adrs/0030-s2s-calls-from-runtime-to-actions.md) (abuse reporting, audit logs), you'll also need the `dreamlifter-dev` key:

```
cd ~/src/azdevnext/src

# Initialize Skyrise environment
./init.sh

# Start LightRail
lr actions

# Retrieve the private key and cert
(Get-SecretCredential vault://actionsauthtest/dreamlifter-dev-auth).password > /{full-path-to-launch}/tmp/azure-dev.private.pem
```

## Dependencies

- A working `github/github` instance
- A working Actions Service instance

## Running

### Standard Mode

1. Start `github/github` locally using `script/server`.
1. Start `github/launch` locally using `script/server`.
1. Navigate to [github.localhost](http://github.localhost), create and trigger a workflow.

### Multi-tenant Mode

1. Start `github/github` locally in multi-tenant mode using `script/server --multi-tenant`.
1. Start `github/launch` locally using `API_HOST=http://internal-api.service.ghe.localhost LAUNCH_IS_MULTI_TENANT=true script/server`.
1. Navigate to [avocado-gmbh.ghe.localhost](http://avocado-gmbh.ghe.localhost) and log in as `monalisa_avo`.
    - Alternatively, [`ghe.localhost`](http://ghe.localhost) allows you to login to a specific tenant using a drop down.
    - The username follows the pattern `monalisa_<tenant shortcode>`.
1. Create and trigger a workflow (you may need to [configure](https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners/adding-self-hosted-runners) at least one actions-runner for your repo, org, or enterprise).

### Aqueduct

`aqueduct-lite` is vendored in Dotcom and listens on port `18081`
https://github.com/github/github/blob/master/script/aqueduct-lite-server
You can also use full aqueduct, please follow the steps in the aqueduct repo for setting it up.

## Database migrations

To keep your local development database up to date you can use skeema by doing `script/skeema push`.

More on migrations and transitions [here](migrations-and-transitions.md).

## Triggering workflows

It often takes a long time for a push event to be sent to `launch`, so for frequent testing it might be better to trigger workflows with `repository_dispatch`:

1. [Generate](http://github.localhost/settings/tokens/new?scopes=repo&description=Token%20for%20repository_dispatch) a PAT with the `repo` scope.
1. `POST` to the `/dispatches` endpoint to trigger the webhook:

```bash
curl -v -u "monalisa:<PAT>" -H "Accept: application/vnd.github.everest-preview+json" \
  -H "Content-Type: application/json" --data '{"event_type":"<some event>"}' \
  http://api.github.localhost/repos/<nwo>/dispatches
```

## Using secrets

Secrets are stored in the `kredz` service which uses `diet_earthsmoke` for it's encryption / decryption use cases.

To reset the database, go to the Kredz workspace and truncate the `credz` table:

```shell
cd /workspaces/kredz
script/dbconsole credz

truncate table credentials;
```

## Trigger workflow-healing job

1. Comment out [this validation](https://github.com/github/launch/blob/505a00ad90dc707a693692ecc068d2264e43fb65/cmd/job-cli/healbuilds/healbuilds.go#L89) regarding database write access
2. Change [the `queueRunGracePeriod`](https://github.com/github/launch/blob/505a00ad90dc707a693692ecc068d2264e43fb65/cmd/job-cli/healbuilds/constants.go#L13) to `time.Second` if you want to force cleanup without waiting 50h
3. After the above changes, restart launch:

```bash
service launch stop && script/build && service launch start
```

4. Dot source server environment variables

```bash
. script/_serverenv
```

5. Run the job and specify the desired time ranges, e.g.

```bash
DEPLOYER_DATABASE_READ_ONLY_URL="$DEPLOYER_DATABASE_URL" ./bin/job-cli jobs healWorkflows -p 1s -t 1s
```

For usage, refer

```bash
DEPLOYER_DATABASE_READ_ONLY_URL="$DEPLOYER_DATABASE_URL" ./bin/job-cli jobs healWorkflows --help
```

## With Driftwood/Audit Logging/Hydro

See [local-dev-hydro-kafka](./local-dev-hydro-kafka.md)

## Testing

See the [testing doc](./testing.md).

## Adding Chatops

See the [chatops doc](./chatops.md)

## Issues

### Unable to retrieve S2S token

If you see errors like `Registration was not found or is not medium trust` when connecting to the ADN token service locally:
Either force setup (that will re-create the database):

```
script/setup --force
```

Or: reset just the AZP tenant information in the deployer database: `script/dbconsole deployer` then `truncate table azp_resources;`

## Related Reading

https://github.com/github/scripts-to-rule-them-all

## Debugging

See [debugging doc](./debugging.md)

#### Verify changes in GHES

https://github.com/github/c2c-actions/blob/master/docs/ghes/bp-dev.md#how-do-i-use-changes-for-launch-on-my-bp-dev-instance
