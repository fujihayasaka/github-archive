# MCP E2E Agent Setup

This document outlines how to get the GitHub MCP server working in a codespace and optional configuration for a simple `echo` server with OIDC authentication.

## Prerequisites

1. A created codespace by following the main [E2E service dev setup](e2e-service-dev-setup.md) article.
1. If you intend to use the echo server with OIDC authentication, you will need an Entra ID instance and the necessary client credentials to configure OIDC. You'll already have one if you have an Azure subscription.

## GitHub MCP Server

### Setup


1. Clone the github-mcp-server-remote repository:

    ```bash
    cd /workspaces && git clone https://github.com/github/github-mcp-server-remote.git
    ```

1. Navigate to the MCP server directory and set the required environment variables. Note: we use port 2219 instead of the default to avoid conflicting with the sweagentd Twirp server, which runs on
   the same default port

    ```bash
    cd /workspaces/github-mcp-server-remote
    export OTEL_RESOURCE_ATTRIBUTES="service.name=github-mcp-server-remote"
    export GITHUB_TELEMETRY_LOGS_LEVEL="debug"
    export GITHUB_API_URL="http://api.github.localhost/"
    export PORT=2219
    ```
1. Start the server
   
   ```bash
    go run ./cmd/http/main.go
   ```

1. Update your `.env` file for sweagentd with the necessary config:
    ```
    COPILOT_MCP_ENABLED=true
    GITHUB_MCP_URL_OVERRIDE="http://localhost:2219/mcp"
    DOCKER_HOST_NETWORKING=true
    ```

1. Restart sweagentd if it's already running to pick up the new config

Tip: Use the copilot cli to help troubleshoot any issues that arise when trying to set up and use the github mcp server

## Echo Server [Optional]

The optional echo server can be used to test MCP scenarios including authentication in a local codespace, staging, or production environment. Here's how to set it up and run it.

### Setup

1. For use in development (in a codespace), update your sweagentd `.env` file to enable MCP support:
    ```
    COPILOT_MCP_ENABLED=true
    ```

1. Enable the token exchange feature flag.

    In development:

    ```bash
    /workspaces/github/bin/toggle-feature-flag enable copilot_swe_agent_oidc_token_exchange
    ```

    Or use [add yourself here for use in staging / prod](https://devportal.githubapp.com/feature-flags/copilot_swe_agent_oidc_token_exchange/targeting-rules/actors-view?stamp=dotcom).

1. Clone the mcp-auth-test-server repository:

    ```bash
    cd /workspaces && git clone https://github.com/github/mcp-auth-test-server.git
    ```
1. Run npm install:

    ```bash
    cd /workspaces/mcp-auth-test-server && npm install
    ```

1. **[Optional]** In VS Code, add the `/workspaces/mcp-auth-test-server` folder to your workspace so you can use the two debug targets (`OIDC - MCP Server Debug`, `OIDC - OIDC Server Debug`).

### Quick start: Remote MCP w/o Entra ID
The easiest setup is the remote MCP server which can be used for development, staging, or production with slightly different config.

1. In your Codespace, forward the relevant port based on the environment you want to use the MCP server from.
   - **Development**: Port 3125
   - **Staging / Production**: Port 2208 (sweagentd)

1. Make this port public by right-clicking on the port in the Codespaces port forwarding tab, selecting Port Visibility, then Public.

    > Note that you may need to do this each time you start up or the server is restarted.

1. Click on the copy icon to copy the port forwarded URL.

1. From the cloned `mcp-auth-test-server` repository, copy the `.env.example` file to `.env`
    1. Uncomment `SKIP_ENTRA_EXCHANGE=true` at the top of the `.env` file.
    1. Set the following variables depending on whether you want to use it during development (in a codespace) or from staging/production:

    | Variable | Development | Staging / Production |
    |-------------|-------------------|-------------------|
    | `GITHUB_OIDC_ISSUER` | Port forwarded URL from above | `https://github.com/login/oauth` |
    | `HOST_URL` | `http://localhost:3125` or leave commented out | Port forwarded URL from above |

1. Start the MCP server:

    ```bash
    cd /workspaces/mcp-auth-test-server && npm run dev:remote
    ```
    Or use the VS Code debug target `OIDC - MCP Server Debug`.

1. Add a custom agent config to a repository that has the correct URL based on whether you are in development (codespace) or staging/production.
    * **Development:** `http://localhost:3125/mcp`
    * **Staging / Production:** `<port forwarded URL from above>/mcp`

    For example:
    ```
    ---
    name: Echo Joker
    description: This agent generates a joke and sends it to the echo tool
    tools: [ "oidc-test/echo" ]
    mcp-servers:
      oidc-test:
        type: http
        url: https://example-codespace-blah-3125.app.github.dev/mcp
        tools: ["*"]
        oidc:
          audience: "https://login.microsoftonline.com/common/v2.0"
          agent-only-subject: true
    ---

    Come up with a funny joke based on the prompt and send it to the echo tool.
    ```

1. Use any surface in GitHub or VS Code or the job / task API that lets you reference the custom agent when creating a job.

### Full development setup w/Entra ID

1. Start up github:

    ```bash
    cd /workspaces/github && script/dx/start-server
    ```

1. Get some info needed for the OIDC setup:
    1. Get the Copilot SWE Agent **GitHub App client ID** by going to http://github.localhost/organizations/github/settings/apps/copilot-swe-agent
    1. Get the github org's ID. In bash in your codespace, run `GITHUB_TOKEN=$MONALISA_PAT gh api graphql -f query='{ organization(login: "github") { id databaseId } }' --hostname github.localhost`


1. Setup Entra:
    1. In the Azure portal, go to your Entra ID instance and create a new app registration. Take note of the `Application (client) ID` and `Directory (tenant) ID` since we will use these multiple times.
    1.  Click on `Certificates & secrets` and create a new client secret. Take note of the value since we will use it in the `.env` file.
    1. Create a federated credential for the GitHub App in your Entra ID app registration. This will allow the GitHub App to request tokens from Azure AD using OIDC.
        1. Select "Other issuer"
        1. Issuer: `https://your-codespace-2208.app.github.dev` replacing `your-codespace` with the name of your codespace with dashes instead of spaces.
        1. Select "Explicit subject identifier", with a value of `app:{copilot-swe-agent-client-id-here}:owner_id:org_id:{github-org-id-here}`
        1. Under Audience, click edit and enter `https://login.microsoftonline.com/common/v2.0`
        1. Give it any name you want

1. 1. From the cloned `mcp-auth-test-server` repository, copy the `.env.example` file to `.env` and update it with your OIDC client credentials.

    1. Update `AZURE_TENANT_ID`, `AZURE_CLIENT_ID`, and `AZURE_CLIENT_SECRET` in the `.env` file with the values from your Entra ID app registration.
    1. Update `TOKEN_SCOPES` with your client ID in the location in the example.
    1. Replace `your-codespace` with the name of your codespace with dashes instead of spaces in each spot in the `.env` file.
    1. Run `node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"` and place that value in `ENCRYPTION_KEY` property.

#### Running the Echo servers

In addition to the debug configuration, you can use the following commands to start the different servers.

1. Start sweagentd
2. Update port forwarding in your codespace to make port 2208 **publicly accessible**. This is only required while doing ODIC testing.
3. Start up the appropriate servers. The remote MCP server is by far the easiest to get running for testing purposes. See below:

| Server | Command |
|--------|---------|
| Remote Echo MCP Server | `cd /workspaces/mcp-auth-test-server && npm run dev:remote` |
| Stand alone OIDC server for use with the Local MCP server | `cd /workspaces/mcp-auth-test-server && npm run dev:oidc` |
| Local Echo MCP Server (requires stand-alone OIDC server running) | `cd /workspaces/mcp-auth-test-server && npm run dev` |

Temporarily publish the MCP server to your own personal `npm` account via `npm publish` so it is accessible for testing. 

While there's nothing sensitive in the package, it's recommended to delete it when not in use.

#### Remote MCP server testing setup

Add the following custom agents to the `github/private-server` repository in your codespace under `.github/agents/echo-joker.agent.md`.
```
---
name: Echo Joker
description: This agent generates a joke and sends it to the echo tool
tools: [ "oidc-test/echo" ]
mcp-servers:
  oidc-test:
    type: http
    url: http://localhost:3125/mcp
    tools: ["*"]
    oidc:
      audience: "https://login.microsoftonline.com/common/v2.0"
      agent-only-subject: true
---

Come up with a funny joke based on the prompt and send it to the echo tool.
```

#### Local MCP server testing setup

Add the following custom agents to the `github/private-server` repository in your codespace under `.github/agents/echo-joker-local.agent.md`. Updating:
- The `AZURE_TENANT_ID` and `AZURE_CLIENT_ID` values
- The name of the npm package you published for the local MCP server.


```
---
name: Echo Joker Local
description: This agent generates a joke and sends it to the echo tool
tools: [ "oidc-test/echo" ]
mcp-servers:
  oidc-test:
    type: stdio
    command: "npx"
    args: ["mcp-auth-test-server"]
    tools: ["*"]
    env:
      MCP_ACCESS_TOKEN: "$GITHUB_COPILOT_OIDC_MCP_TOKEN"
      AZURE_TENANT_ID: "your-azure-tenant-id"
      AZURE_CLIENT_ID: "your-azure-client-id"
    oidc:
      endpoints:
        base: "http://localhost:3124"
      audience: https://login.microsoftonline.com/common/v2.0
      agent-only-subject: true
---

Come up with a funny joke based on the prompt and send it to the echo tool.
```

#### Running a test

With all the appropriate servers, you can use the following Job API script calls to trigger the workflow:

```bash
script/job-api new github/private-server '{"problem_statement":"create a doc about humor and tell a joke", "custom_agent":"echo-joker"}'
```

Or for the local MCP server:

```bash
script/job-api new github/private-server '{"problem_statement":"create a doc about humor and tell a joke", "custom_agent":"echo-joker-local"}'
```
