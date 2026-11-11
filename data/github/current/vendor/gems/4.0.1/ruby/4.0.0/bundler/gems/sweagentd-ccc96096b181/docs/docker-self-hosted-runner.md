# Docker Self-Hosted Runner

If you are using the Actions launcher, it uses this docker self-hosted runner by default. This prevents the AI from having complete access to the codespace and enables certain features like the on-host **firewall** over the default self-hosted runner installed in the Actions codespace setup.

The docker self-hosted runner is set up with default settings by [`script/setup-codespaces-copilot-swe-agent`](https://github.com/github/github/blob/master/script/setup-codespaces-copilot-swe-agent). This doc covers setting it up manually to change the configuration or in case something goes wrong.

Let's walk through how to set it up and use it:

## Setup

1. Create a new github/github + Actions Codespace and set up sweagentd.

1. Open a terminal and go to the root of the `sweagentd` repo (`/workspaces/sweagentd` if you are in a codespace).

1. [Optional] Set the image and user you want to configure the runner to use. It's recommended to use a Dev Container image since these typically have all the core tools you'd need. Run the following command to set the image and user:

   ```bash
   script/docker-self-hosted-runner set <image> <user>
   ```

   For example:

   ```bash
   script/docker-self-hosted-runner set mcr.microsoft.com/devcontainers/typescript-node:24-bookworm node
   ```

   The utility defaults to `mcr.microsoft.com/devcontainers/typescript-node:24-bookworm` and `node` if not set.

1. Next, go to [Actions runner setup](http://github.localhost/organizations/github/settings/actions/runners) for the github organization and:

   1. Select **Add runner**
   1. Select **New self-hosted runner**
   1. Select **Linux**
   1. Copy the `./config.sh` command line under **Configure** in the instructions that appear.
   1. Pass this command as arguments into the utility. For example:

      ```bash
      script/docker-self-hosted-runner ./config.sh --url http://github.localhost:80/github --token <token>
      ```

   1. Follow the directions that then appear. You can name the runner anything you want, but when prompted add the following label: `docker-self-hosted-runner`.
   1. You can verify the runner is set up correctly by going back to [Actions runner setup](http://github.localhost/organizations/github/settings/actions/runners) and checking that the runner is listed there.

## Usage

1. Once the runner is configured, you can start it by running:

   ```bash
   script/docker-self-hosted-runner
   ```

1. Finally, update your `.env` file for `sweagentd` to include the following:

   ```env
   AGENT_LAUNCHER="actions"
   ACTIONS_DEFAULT_RUNS_ON_LABELS="docker-self-hosted-runner"
   # If you want to validate the firewall too set
   COPILOT_AGENT_FIREWALL_ENABLED_DEFAULT="true"
   ```

That's it! The next time you spin up `sweagentd` it will be configured to interact with the Docker self-hosted runner. Shut down the runner using `CTRL+C`. You can then restart it by running `script/docker-self-hosted-runner` again.

To start over, just delete the `actions-runner` sub-folder, next to this script, in the self-hosted runner config in the github org, click `...` next to the runner and select **Remove runner**, the **Force remove runner**. You can then follow these directions again.
