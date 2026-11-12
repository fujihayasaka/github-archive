# Developing the GitHub Copilot coding agent

## Setting up your `github/github` Codespace

1. Create a codespace for `github/github`:
    - **use the Actions Development Codespace** definition [![Actions Development Codespaces Prebuilds](https://github.com/github/github/actions/workflows/codespaces/create_codespaces_prebuilds/badge.svg)](https://github.com/github/github/actions/workflows/codespaces/create_codespaces_prebuilds)
        - Reach out to [#padawan-actions-collab](https://github-grid.enterprise.slack.com/archives/C08GE21TJ3B) if the Codespace prebuild status is failing.
    - **select the 32-core 256GB machine type**. 
        - The default is 128GB which is not enough
        - You can [feature flag yourself](https://devportal.githubapp.com/feature-flags/codespaces_linux_32core_256gb/targeting-rules/actors-view?stamp=dotcom) into this if you don't see the 256GB option.
    <br />
    <details>
    <summary>Details</summary>
    Because Copilot coding agent relies on interaction within GitHub.com, and compute execution within Actions, the easiest way to develop the full product experience of Padawan is to use a <code>github/github</code> codespace. Use the VS Code Codespaces extension to create a new codespace for <code>github/github</code> and select the <strong>Actions Development</strong> devcontainer.json.<br /><br />

    ![Actions Developer devcontainer](https://github.com/user-attachments/assets/a942caca-51ea-45d0-bb53-2d8ebb565e63)<br /><br />

    Be sure to also **select the 32-core 256GB machine type**. The default is 128GB which is not enough. You can [feature flag yourself](https://devportal.githubapp.com/feature-flags/codespaces_linux_32core_256gb/targeting-rules/actors-view?stamp=dotcom) into this if you don't see the 256GB option.

    Here's a [link to create the codespace configured on web](https://github.com/codespaces/new?skip_quickstart=true&machine=xLargePremiumLinux256gb&repo=3&ref=master&devcontainer_path=.devcontainer%2Factions%2Fdevcontainer.json).

    Optionally, you can also add this `gh` cli alias to create and open a new Codespace in VS Code Insiders:

    ```sh
    gh alias set --shell sweagentd 'gh cs code --insiders -c "$(gh cs create -R 'github/github' --devcontainer-path '.devcontainer/actions/devcontainer.json' -b 'master' -m 'xLargePremiumLinux256gb')"'
    ```

    Once set run:

    ```sh
    gh sweagentd
    ```

    The first time this is run you may need to follow a link to authorize the Codespace permissions.
    </details>

2. Open the codespace in local VS Code using the [GitHub Codespaces extension](https://marketplace.visualstudio.com/items?itemName=GitHub.codespaces).
    - **Do not use the web version of VS Code**.
    - On macOS, enter your password when prompted so it can forward port 80.

3. Pull latest changes and update the databases
    1. Open a terminal in your codespace
    1. **(Optional)** Run `script/dx/shallow-pull` to ensure your environment is up to date. You can skip this unless you really need the latest monolith changes.
    1. **(Optional)** Run `bin/rake db:migrate db:test:prepare` to migrate and prepare the databases. You can skip this unless you really need the latest monolith changes. If ruby is out of date on the codespace, you may need to run this script twice (it will succeed after the ruby version mismatch error).
    1. Start dotcom server in the background `script/dx/server-start` (or `script/server` if you prefer to keep it foregrounded).
    1. Open the browser window when prompted and wait for this to tell you the server is started. If you get a `404` or other error in this window, refresh the browser until it succeeds - do not proceed until it is fully up.
4. Configure runtime hosting and launching for sweagentd using Actions:
    ```sh
    bin/setup-codespaces-copilot-swe-agent
    ```
    > [!TIP]
    > While not required for the dev setup, you can [make it so your codespaces can access CAPI secrets](https://github.com/github/copilot-api/blob/main/docs/dev/dotcom-codespaces-development.md#set-secrets). This will automatically load the HMAC Key for you. **In order to host CAPI this is required**

    - Add `--capi` if you want to host CAPI as well
    - The script will prompt you to input the CAPI HMAC key, see below for how to get it from 1Password.
    - This sets up docker self-hosted runner, [see here for more info](./docker-self-hosted-runner.md).
    - This process will take a while to complete since it may need to set up Actions infrastructure.

<details>
<summary>5. Open a VS Code window for sweagentd</summary>

```sh
code /workspaces/sweagentd/sweagentd.code-workspace
```
</details>

6. Ensure "four nines" feature flags are enabled from **bash**:
   ```bash
   /workspaces/actions/actions-dotnet/src/Scripts/toggle-four-nines on
   ```
   > [!NOTE]
   > This step ensures Actions infrastructure is properly configured. It's not clear if it's always needed, but it ensures a working environment.

7. Start a dockerized Actions self-hosted runner from **bash**:
   ```bash
   start-actions # Optional - makes sure Actions is running
   /workspaces/sweagentd/script/docker-self-hosted-runner
   ```

8. Go to http://github.localhost in a browser - Sign in as `monalisa`

9. Disable feature flags that may interfere with development:
   ```bash
   /workspaces/github/bin/toggle-feature-flag disable actions_launch_run_service_plan_owner
   /workspaces/github/bin/toggle-feature-flag disable github_models_launch_permissions
   /workspaces/github/bin/toggle-feature-flag disable copilot_swe_agent_firewall_enabled_by_default
   /workspaces/github/bin/toggle-feature-flag disable copilot_swe_agent_safe_runtime_deploy
   /workspaces/github/bin/toggle-feature-flag disable copilot_api_agent_sessions
   ```
   > [!NOTE]
   > These feature flags can cause issues in development environments and should be disabled for a working setup.

10. (If not using local CAPI) Add following secrets to [the `@github` organization under actions](http://github.localhost/organizations/github/settings/secrets)

   1. `COPILOT_INTEGRATION_ID_OVERRIDE: copilot-developer-dev`
   2. `CAPI_HMAC_KEY_OVERRIDE` - You can find the value for the HMAC secret in 1Password (called `CAPI / Copilot Developer (Dev) API secret`). This requires [entitlements](https://github.com/github/copilot-api/blob/main/docs/dev/dev-onboarding.md#entitlements).

11. Start up sweagentd
   > **Note:** Be sure you've already started the GitHub server before proceeding.
   
   ### Option A: Using Cosmos DB Emulator (Recommended)
   For a more realistic development environment that can catch race conditions and other issues that only appear with real Cosmos DB:
   
   ```bash
   cd /workspaces/sweagentd
   script/cosmos-dev start  # Start Cosmos DB emulator
   script/server           # Start sweagentd (will automatically use emulator)
   ```
   
   ### Option B: Using In-Memory Store (Default fallback)
   <details>
   <summary>To start <code>sweagentd</code> with in-memory store</summary>
   &nbsp;&nbsp;&nbsp;&nbsp;1. <code>cd /workspaces/sweagentd && script/server</code><br />
   &nbsp;&nbsp;&nbsp;&nbsp;2. Let this run in the background
   </details>
   
   ### Option C: Debugging
   <details>
   <summary>To debug <code>sweagentd</code></summary>
   &nbsp;&nbsp;&nbsp;&nbsp;1. Be sure you have a VS Code window open for <code>/workspaces/sweagentd</code> or a workspace that includes it<br />
   &nbsp;&nbsp;&nbsp;&nbsp;2. Select the <code>Debug sweagentd (launch)</code> configuration<br />
   &nbsp;&nbsp;&nbsp;&nbsp;3. Press F5
   </details>
    <details>
   <summary>To cycle <code>sweagentd</code></summary>
   &nbsp;&nbsp;&nbsp;&nbsp;1. <code>cd /workspaces/sweagentd && script/server</code><br />
   &nbsp;&nbsp;&nbsp;&nbsp;2. <code>cd /workspaces/sweagentd && script/server --sync-runtime</code> if you make changes to the runtime
   </details>
   
   > **💡 Tip:** The Cosmos emulator provides a more realistic development environment and can help catch race conditions that only appear with real Cosmos DB. See [docs/cosmos-emulator-dev.md](cosmos-emulator-dev.md) for more details.

Try it out!

1. Go to a private repo in the `@github` organization like [github/private-server](http://github.localhost/github/private-server) (but do **not** use anything under `monalisa` - it won't work.)
2. Create an issue in the repo, assign Copilot
<details>
<summary>What tells me it's working?</summary>

If everything's working, you should see Copilot:

- React with an :eyes: emoji
- Open a new pull request
- Kick off an Actions workflow

You'll see activity in the `sweagentd` logs.

</details>

## Starting up after a codespace restart

You can start up the codespace again by running the following commands in **bash**:

```bash
/workspaces/github/script/dx/server-start # or /workspaces/github/script/server if you prefer to keep it foregrounded
/workspaces/actions/actions-dotnet/src/Scripts/toggle-four-nines on # ensure Actions infrastructure is configured
start-actions
/workspaces/sweagentd/script/docker-self-hosted-runner

# Option A: With Cosmos DB emulator (recommended)
/workspaces/sweagentd/script/cosmos-dev start
/workspaces/sweagentd/script/server

# Option B: With in-memory store (fallback)
/workspaces/sweagentd/script/server
```

## Testing the Job API

The `sweagentd` service provides a [Job API](./docs/adr/0001-create-job-api.md) that allows you to kick off, get status on, and cancel coding agent jobs. Since this can have unique challenges, be sure you run a test of the API before deploying your changes.

To make this easy, the `script/job-api` script is simple wrapper around the needed curl calls. You can use it against a `--local` environment for testing in a codespace, the `--staging` environment, or even triage problems in `--production`.

For example, this will create a simple new job in your codespace:

```bash
script/job-api new github/private-server '{"problem_statement":"Improve the README."}'
```

More examples and usage can be found by running:

```bash
script/job-api --help
```

## What model should I use?

The feature flag `sweagentd_use_candidate_model_as_default` determines whether you will use the stable model or the new, next model.

For new, next model: `bin/toggle-feature-flag enable sweagentd_use_candidate_model_as_default`

For stable model: `bin/toggle-feature-flag disable sweagentd_use_candidate_model_as_default`

You will also need to enable the model for the organization. Navigate [here](http://github.localhost/organizations/copilot-enterprise-org/settings/copilot/models) and allow the correct model.

## Deploying the runtime

This section is only applicable if you've updated the runtime and are launching using actions

While using Actions as the runner, the runtime is acquired through an action that is deployed into your codespace's GitHub instance [here](http://github.localhost/github/copilot-developer-action). To update it:

1. Create a `.env.local` file from `/runtime/.env.local.example`
2. **[Optional]** If you have the firewall enabled, use **public** github.com to generate a [fine grained token](https://github.com/settings/personal-access-tokens) with read-only "Contents" access to https://github.com/github/ebpf-padawan-egress-firewall.
3. Copy the token into the `.env.local` file as the value for `EBPF_DOWNLOAD_GITHUB_TOKEN`.

From there, any time you want to deploy updated runtime contents, just run:

```bash
/workspaces/sweagentd/runtime/script/action-sync-repo
```

That's it!

## Local CAPI Specific Setup

These are additional setup steps you need if you ran `setup-codespaces-copilot-swe-agent` with the `--capi` flag.

### Allow models in github policy

You'll want to go to an organization settings page ([here](http://github.localhost/organizations/github/settings/copilot/models) if you're using `github/private-server` for testing), and enable whatever model CCA is using at the time. If you don't know, feel free to enable them all. If you do not do this, you'll see errors like `The requested model is not supported` in your actions logs.

## Tips

Here are some tips for common issues that you may encounter:

### Actions

- Many Actions problems can be fixed by stopping your runner and executing the following commands in **bash**:
    ```bash
    start-actions
    /workspaces/sweagentd/script/docker-self-hosted-runner
    ```
    If this does not work, try fully shutting down your codespace (**F1** > **Codespaces: Stop Current Codespace**), restarting it, and then spinning things up again.

- If your Actions docker-self-hosted-runner is still not picking up work, it's possible that "four nines" feature flags were not properly set during setup or were reset due to a database migration after updating github/github. To resolve:
    1. Shut down the docker-self-hosted-runner
    2. Re-run step 6 from the setup process: `/workspaces/actions/actions-dotnet/src/Scripts/toggle-four-nines on`
    3. The previous step should restart Actions for you. If not, you can also try re-running `start-actions` in bash before starting the runner.
    4. Be sure all steps pass, then restart the runner. 

- If the Actions UI is failing with:

    ````
    [Internal Error] The job could not retrieve the repository token. [Production Message] GitHub Actions has encountered an internal error when running your job.```
    ````

    Run `bin/rake db:migrate db:test:prepare` then `bin/seed github_repo --nwo github/copilot-developer-action -t $GITHUB_TOKEN` to fix

- If you copied over your own .env file, ensure your environment has `ACTIONS_DEFAULT_RUNS_ON_LABELS=docker-self-hosted-runner` set in `/workspaces/sweagentd/.env`

- If the "Prepare Copilot" step fails with `Process completed with exit code 22`, try running the following command and triggering a new job:

    ```
    /workspaces/sweagentd/runtime/script/action-sync-repo
    ```

- If after assigning an issue to Copilot, the PR is created but the agent fails to start, and you see errors in `sweagentd`'s logs about 401's when trying to POST to `https://api.githubcopilot.com/agents/sessions`, ensure you've completed step 9 in the setup process to disable the necessary feature flags. If you haven't, run:

    ```
    /workspaces/github/bin/toggle-feature-flag disable copilot_api_agent_sessions
    ```

    ...and then re-start `sweagentd`. You won't have the session logs, but you can use the actions logs to monitor the agent's progress.

- See **[Actions inner loop troubleshooting documentation](https://github.com/github/c2c-actions/blob/main/docs/actions-development/innerloop-debugging.md)** or reach out to `#actions-inner-loop` on Slack.

- If your local runner is not picking up the job, try stopping your runner, running `service stop launch`, followed by `start-actions` and `script/docker-self-hosted-runner` again.

- If you are encountering an Overmind error while starting the server, like `overmind: it looks like Overmind is already running. If it's not, remove /tmp/overmind-authnd.sock and try again`, try updating your branch (`git pull`) and trying again.

### Aqueduct

- sweagentd integrates with [Aqueduct](https://thehub.github.com/epd/engineering/products-and-services/internal/aqueduct/) for job queueing. To update protobuf files after updating the `.proto` files, run `go generate` command from the command line (e.g. `go generate ./internal/aqueduct/jobs/...`) and commit the generated files as well.

### General

- Always restart sweagentd if you restart the github server. Otherwise events will not flow properly into the service code.

- Only use **private** repositories in the **github** organization in your GitHub instance for testing. Others won't work.

- If you want to edit code for repositories inside your GitHub instance you can clone them and there's a default PAT to make this easy. For example, to clone `github/private-server`, run:

    ```
    cd /workspaces
    git clone http://monalisa:ghp_MonalisaTheOctoPatMonalisaTheOctoPat@github.localhost/github/private-server
    ```

- You can "seed" existing repositories in the https://github.com/github org into your GitHub instance as well. Run `bin/seed github_repo --nwo github/your-repo-name-goes-here -t $GITHUB_TOKEN`

- If you use `zsh`, make sure to use `bash` for commands in `/workspaces/github`. There are aliases mentioned in docs in “the hub” that won't work by default. E.g. `start-actions` won't be in zsh, but will be in bash. You can copy the aliases from `~/.bashrc` to `~/.zshrc` if you prefer.

- If **port forwarding** stops working in VS Code (particularly for port 80), use **Reload Window** from the command palette (F1 or Ctl/Cmd+Shift+W) to get it to kick in again.

- If you started the dotcom server in the background, you can stop it with `script/dx/server-stop`.

- You can enable debug level logging in the runtime by setting an Actions variable `COPILOT_AGENT_DEBUG` with a value of `true`.

- If upon trying to assign an issue to Copilot you see an error like "could not update assignee" then:
    1.  Stop the dotcom server
    2.  Re-run `bin/rake db:migrate db:test:prepare`
    3.  Re-run `bin/setup-codespaces-copilot-swe-agent`
    4.  Start the doctcom sever

### Environment issues

- If you start getting warnings about disk being full, delete the logs in `/workspaces/github/log`. They can get shockingly large.

- If you encounter `403` / access denied errors in `sweagentd` while trying to access `api.github.com`, make sure your `GITHUB_APP_PRIVATE_KEY`, `GITHUB_APP_ID` and `GITHUB_BOT_ID` are correct. This is a common "gotcha" if you copy your `.env` file from another codespace.

- If you run into errors about database tables, shut down your server, run `bin/rails db:migrate` and then `script/bootstrap` and then `bin/server`, and after your instance is up, run `start-actions` again from `bash`. If you are still hitting problems you may need to start over and create a new codespace.

- These problems are tough to recover from, so just **start over with a new codespace** if you hit them:
    - There is no Actions runner in the github org. (See http://github.localhost/github => Settings => Actions => Runners)
    - The [Copilot SWE agent app](http://github.localhost/apps/copilot-swe-agent) is missing.

See [here for documentation](https://github.com/github/c2c-actions/blob/main/docs/actions-development/scenarios/actions-codespaces-vnext.md) on how Actions Development codespace is set up.

### Things NOT to do

- Do **not** run `bin/setup --force` if prompted. You shouldn't need it and it wipes out all data so you'll have to start over. Just create a new codespace if you do this by mistake.

- **Avoid** using `docker system prune`. This will delete all of the images and containers on your machine and images that can force you to have to create a new codespace.

- Do **not** try to rebuild your codespace. It will fail and you can get in an unrecoverable state. Always create a new one instead to pick up changes to the dev container config.
