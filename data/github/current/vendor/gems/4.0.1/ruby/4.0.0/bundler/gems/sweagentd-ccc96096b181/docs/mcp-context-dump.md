# Extending Padawan with Local MCPs context sharing

This document is accurate as of **May 12th, 2025**. It's purpose is to write down all the "Extending Padawan with local MCP" related things to transfer context. The original gist is located here <https://gist.github.com/belaltaher8/fb6781c8ec3fb466f5cbb0ed9055bd10>

## User Experience

Currently, a user configures their local MCP servers through Repository Settings. On the left side bar, navigate to `Copilot`. Click on `Coding Agent`. This form is where you specify your MCP servers.

![Screenshot 2025-05-11 at 8 47 16 PM](https://gist.github.com/user-attachments/assets/82ffc355-d0b6-4a85-aae9-aacdfe440d1c)

A user can also [supply variables and secrets](https://github.com/github/sweagentd/blob/469154a/internal/launcher/actions_workflow.yaml#L105-L111) that only get threaded to the environment of the MCP step on the actions runner. The user does this through Repository settings. On the left side bar navigate to `Environments`. Create a new environment called `copilot`. If you create any `Variables` / `Secrets` that have the `COPILOT_MCP` prefix, [they will be extracted out from the runtime's environment and only threaded to the MCP step's env](https://github.com/github/sweagentd/blob/469154a8bf066a502076da796aebd1282e24b302/internal/launcher/actions.go#L340-L367).

![Screenshot 2025-05-09 at 1 25 12 PM](https://gist.github.com/user-attachments/assets/a67eae0a-7f71-4a04-8c5d-ba5266cb1bbe)

### Configuring 1P MCPs

In Padawan we have 1P MCPs (GitHub MCP & Blackbird MCP) and 3P MCPs. The 1P MCP are bundled in natively in. The [blackbird MCP is built from source](https://github.com/github/sweagentd/blob/a22ca30698e6512fda71053b871da08846d27f32/runtime/script/blackbird-mcp-build) & the [GitHub MCP is pulled in](https://github.com/github/sweagentd/blob/a22ca30698e6512fda71053b871da08846d27f32/runtime/script/github-mcp-pull). These servers are configured with the [following defaults](https://github.com/github/sweagentd/blob/a22ca30698e6512fda71053b871da08846d27f32/mcp-client/src/ServerConfigProcessor.ts#L52-L90).

```
const githubMCPServerConfig: MCPServerConfig = {
  command: "./copilot-developer-action-main/github-mcp-server/github-mcp-server",
  args: ["stdio", "--read-only"],
  env: { "GITHUB_PERSONAL_ACCESS_TOKEN": "GITHUB_PERSONAL_ACCESS_TOKEN" },
  tools: ["*"]
};
```

```
const blackbirdMCPServerConfig: MCPServerConfig = {
  command: "./copilot-developer-action-main/blackbird-mcp-server/blackbird-mcp-server",
  args: ["stdio"],
  env: { "GITHUB_PERSONAL_ACCESS_TOKEN": "GITHUB_PERSONAL_ACCESS_TOKEN" },
  tools: toolRestrictions,
};
```

**Note:** The backend supports overwriting the `github-mcp-server` (e.g. user wants to remove the `--read-only` option), but we have chosen not to mention this in public docs yet. Eventually, users will be able to provide new customize `args`, `env`, `tools`, and even `command` (if they don't want to use the build in binary). The only configurability of 1P servers we will expose to end-users is [they can supply `COPILOT_MCP_GITHUB_PERSONAL_ACCESS` token](https://github.com/github/sweagentd/blob/469154a/internal/launcher/actions_workflow.yaml#L101) in their `copilot` environment to grant more privileges to Padawan's GitHub MCP tools.

**Note:** `toolRestrictions` is so we can control whether blackbird operates in `initial-search` or `tool` mode. `initial-search` means it does a tool call at the beginning of the runtime's execution to collect repository insights. `tool` means we expose it to model and allow it to decide when/if to collect repository insights. We currently have `initial-search` mode staffshipped. See picture below for an example of `initial-search`

![Screenshot 2025-05-09 at 1 52 08 PM](https://gist.github.com/user-attachments/assets/3ba4a43d-eca2-40f2-a400-5bafaddf6a20)

### Configuring 3P MCPs

Below is an example of a 3P configuration

```
{
  "mcpServers": {
    "figma": {
      "type": "local",
      "command": "npx",
      "tools": ["*"],
      "args": [
        "-y",
        "figma-developer-mcp",
        "--figma-api-key=$FIGMA_KEY",
        "--stdio"
      ],
      "env": {
        "FIGMA_KEY": "COPILOT_MCP_FIGMA_KEY"
      }
    },
    "playwright": {
      "type": "local",
      "command": "npx",
      "args":["@playwright/mcp@v0.0.32"],
      "tools": ["browser_navigate"]
    }
  }
}
```

```
"server-name":{
  "command": string, # command to start the MCP server with. npx, docker, uvx, python supported
  "args": string[], # args to start the MCP server with.
  "tools": string[], # Subset of tools to include. ["*"] means all, [] means none.
  "type" : string, # Optional. Padawan only accepts "local".
  "env": object{} # Optional. Environment variables to pass to MCP server. None if omitted.
},
```

**Note**: The left side of the `env` how the MCP server will receive that environment variable. The right side is how it's set in the actions workflow environment.

**Note**: In the `args` section, you can directly reference variables you loaded in the `env` section. Note the figma configuration above. `COPILOT_MCP_FIGMA_KEY` is loaded in from the actions environment. Translated to `FIGMA_KEY` for the MCP server. And then in `args` we can use `$FIGMA_KEY` to reference that value. The `$` is required syntax.

**Note**: In order for a `Variable` or `Secret` in the `copilot` environment to end up in the MCP step of the actions workflow, it **must be prefixed** with `COPILOT_MCP_`.

## Implementation details

This section will explain in depth all the different components of our MCP infrastructure

### Relevant Env Vars/FFs

The following environment variables are relevant to the MCP behavior.

- `COPILOT_MCP_ENABLED` - Gates whether or not the Runtime will look for `mcp-config.json` to register the MCP tools. This was intended to be a way for the user to easily disable MCP, but setting this doesn't actually change behavior [and that's a bug](https://github.com/github/sweagentd/issues/1961). It's always true as it gets set by [the Kubernetes configuration](https://github.com/github/sweagentd/blob/469154a8bf066a502076da796aebd1282e24b302/config/kubernetes/production/deployments/sweagentd.yaml#L88-L89) and we directly thread that into [`.MCPEnabled`](https://github.com/github/sweagentd/blob/469154a8bf066a502076da796aebd1282e24b302/internal/launcher/actions.go#L103) which is what's actually used in `actions_workflow.yaml`[[1]](https://github.com/github/sweagentd/blob/469154a8bf066a502076da796aebd1282e24b302/internal/launcher/actions_workflow.yaml#L136) [[2]](https://github.com/github/sweagentd/blob/469154a8bf066a502076da796aebd1282e24b302/internal/launcher/actions_workflow.yaml#L44-L111)
- `COPILOT_MCP_JSON` - ~This is where users set their MCP Servers Configuration. This is only used as a backup if you have `sweagentd_source_mcp_config_from_dotcom` FF.~ This used to be the way to configure your servers. [It has since been removed and replaced by `GITHUB_COPILOT_MCP_JSON`](https://github.com/github/sweagentd/pull/2028). It now has the `GITHUB_` prefix since that prevents users from setting it themselves.
- `GITHUB_COPILOT_3P_MCP_ENABLED` - This environment variables gates the 3P functionality. If this is false, then we throw away their provided server config (so no 3P servers) and give them the default configurations for 1P servers (GitHub + Blackbird)
- `GITHUB_COPILOT_MCP_JSON_FROM_INPUT` - This environment variable is what we get from the [twirp call](https://github.com/github/sweagentd/blob/469154a8bf066a502076da796aebd1282e24b302/internal/launcher/actions.go#L120-L144) to dotcom for the Repository settings form. If we find this we set `GITHUB_COPILOT_MCP_JSON` to this value.
- `GITHUB_COPILOT_MCP_JSON` - This is where we look for users' MCP Server configurations. This replaced `COPILOT_MCP_JSON`. It used to not have the `GITHUB_` prefix since we wanted users to be able to set it through their `copilot` environment. Now that we rely on the Repository settings form and don't want users to be able to set it otherwise, we use this.

The FF's that gate this behavior are mostly staffshipped

- [`sweagentd_mcp_enabled`](https://devportal.githubapp.com/feature-flags/sweagentd_mcp_enabled/overview) - This FF is staffshipped & gates all MCP functionality 1P + 3P.
- [`sweagentd_mcp_3p_enabled`](https://devportal.githubapp.com/feature-flags/sweagentd_mcp_3p_enabled/overview) - This FF is staffhipped & gates allowing 3P customization. This FF is standing in for the policy clicker currently. [See this comment for more context](https://github.com/github/sweagentd/blob/c0c125b/internal/launcher/actions.go#L146-L150)
- [`sweagentd_blackbird_initial_search`](https://devportal.githubapp.com/feature-flags/sweagentd_blackbird_initial_search/overview) - This FF is staffshipped & gates the agent runtime [doing an initial search to gather repository insights](https://github.com/github/sweagentd/blob/9a1366cf5ff6609b1779e6440b7d7eb939bf7f31/runtime/src/agents/swebench.ts#L106-L131).
- [`sweagentd_source_mcp_config_from_dotcom`](https://devportal.githubapp.com/feature-flags/sweagentd_source_mcp_config_from_dotcom/targeting-rules?stamp=dotcom) - This FF is staffshipped & gates whether we load our config in through `COPILOT_MCP_JSON` in the `copilot` environment or use the form on the front-end under `Copilot > Coding Agent`.
- [`copilot_swe_agent_repo_settings`](https://devportal.githubapp.com/feature-flags/copilot_swe_agent_repo_settings/overview) - This FF is staffshipped & gates whether we render the front end form under `Copilot > Coding Agent`.

### Runtime

In the runtime we've added a [MCP-Transport](https://github.com/github/sweagentd/blob/main/runtime/src/tools/mcp-transport.ts). This is in charge of communicating with the all up MCP Server, which [listens](https://github.com/github/sweagentd/blob/main/mcp-client/src/MCPServer.ts#L11) on `localhost:2301`. It knows about all the MCP tools available in the all up MCP server [through a](https://github.com/github/sweagentd/blob/main/runtime/src/agents/swebench.ts#L230) `mcp-config.json`. An [important piece of context here is returning](https://github.com/github/sweagentd/blob/main/runtime/src/tools/mcp-transport.ts#L37-L42) `ToolResultExpanded.sessionLog` is how to get data to the front end Sessions view.

### Launcher & Template

The MCP relevant code in the launcher is around the [`data` object](https://github.com/github/sweagentd/blob/a22ca30698e6512fda71053b871da08846d27f32/internal/launcher/actions.go#L87-L108). We use this object to indicate what [MCP mode we're operating in](https://github.com/github/sweagentd/blob/a22ca30698e6512fda71053b871da08846d27f32/internal/launcher/actions.go#L111-L127) & to [extract our `COPILOT_MCP_` prefix-ed secrets & variables into separate buckets `MCPSecrets` & `MCPVariables`](https://github.com/github/sweagentd/blob/a22ca30698e6512fda71053b871da08846d27f32/internal/launcher/actions.go#L302-L338).

In our [`actions_workflow.yaml`](https://github.com/github/sweagentd/blob/a22ca30698e6512fda71053b871da08846d27f32/internal/launcher/actions_workflow.yaml#L44-L103) template file, the entire `Start MCP Servers` step is gated on `data.MCPEnabled`. Also note we can see the [templating logic](https://github.com/github/sweagentd/blob/a22ca30698e6512fda71053b871da08846d27f32/internal/launcher/actions_workflow.yaml#L92-L103) to thread `MCPSecrets` / `MCPVariables` & set `GITHUB_COPILOT_3P_MCP_ENABLED` (whether to allow 3P MCPs)

### `mcp-client/`

`sweagentd/mcp-client` is where most of the code lives. There's a couple different components. There's a [readme](https://github.com/github/sweagentd/tree/main/mcp-client) that describes how to set this up in dev. [`mcp-client/src/index.ts`](https://github.com/github/sweagentd/blob/e5fcd8cf501a318136aad534f5e767f4d2f2c04f/mcp-client/src/index.ts) is the entrypoint. `index.ts` builds an `MCPRegistry`. It then uses the `ServerConfigProcessor` to read the environment and build the appropriate configuration. Then uses the `ToolConfigWriter` to write an JSON to disk with the information the runtime requires to register the MCP tools. Then starts up the "all-up" `MCPServer` that listens for MCP Tool invocations.

#### MCPRegistry

`MCPRegistry` is class that keeps references to all the individual MCP clients. It [starts up each individual MCP server & saves a reference to its respective client](https://github.com/github/sweagentd/blob/a22ca30/mcp-client/src/MCPRegistry.ts#L24-L59). Also, since it has reference to all the indivdual mcp clients, we need to [iterate over all of them in this class to aggregate our tools](https://github.com/github/sweagentd/blob/a22ca30/mcp-client/src/MCPRegistry.ts#L61-L87).

#### ServerConfigProcessor

`ServerConfigProcessor` is a class that reads the environment and creates the appropriate MCP Server configuration. It checks [`GITHUB_COPILOT_3P_MCP_ENABLED` to see if 3P mode, and reads in `GITHUB_COPILOT_MCP_JSON` if we are in 3P mode, adds the 1P server configs](https://github.com/github/sweagentd/blob/e5fcd8c/mcp-client/src/ServerConfigProcessor.ts#L14-L50). The default 1P server configs can be seen [here](https://github.com/github/sweagentd/blob/e5fcd8c/mcp-client/src/ServerConfigProcessor.ts#L52-L90). This class also filters the [appropriate environment variables to each server and resolves the `$VARS` in the `args` field](https://github.com/github/sweagentd/blob/e5fcd8c/mcp-client/src/ServerConfigProcessor.ts#L179-L207).

It also deals with `python` MCPs. Every other popular MCP command `docker`, `npx`, `uvx` would automatically pull the MCP server onto your machine (docker was usually paired with `run` as one of its args which automatically pulls the image). `python` MCPs don't do that. They assume the user has installed the MCP through pip. To make things easier for ourselves, we [simply search for the `python` module's name using the `-m` flag, and do `pipx run <module_name>` instead](https://github.com/github/sweagentd/blob/e5fcd8c/mcp-client/src/ServerConfigProcessor.ts#L144-L177). `pipx run` functions similarly to `docker` run in that it pulls the required bits first.

#### ToolConfigWriter

The `ToolConfigWriter` is a simple class that [just writes the information required to register the requested MCP tools to the model](https://github.com/github/sweagentd/blob/e5fcd8cf501a318136aad534f5e767f4d2f2c04f/mcp-client/src/ToolConfigWriter.ts). It writes a JSON out to disk that the [agent runtime will look for](https://github.com/github/sweagentd/blob/9a1366cf5ff6609b1779e6440b7d7eb939bf7f31/runtime/src/agents/swebench.ts#L228-L235) if its [running in `COPILOT_MCP_ENABLED` mode](https://github.com/github/sweagentd/blob/9a1366cf5ff6609b1779e6440b7d7eb939bf7f31/runtime/src/agents/swebench.ts#L66-L67).

#### MCPServer

The `MCPServer` is a simple server that just [listens on `localhost:2301` for requests to `/invoke-tool`](https://github.com/github/sweagentd/blob/e5fcd8cf501a318136aad534f5e767f4d2f2c04f/mcp-client/src/MCPServer.ts#L9-L26). With its instance of the `MCPRegistry`, [it grabs the appropriate MCP client for requested MCP server tool call, executes it, and returns the text result as JSON](https://github.com/github/sweagentd/blob/e5fcd8cf501a318136aad534f5e767f4d2f2c04f/mcp-client/src/MCPServer.ts#L47-L74).

## Work In Progress & Desired end state of MSFT Build

We currently have work in progress to add a [3P MCP Policy](https://github.com/github/github/pull/374582). This will hook into [`data.MCP3PEnabled` which controls `GITHUB_COPILOT_3P_MCP_ENABLED`](https://github.com/github/sweagentd/blob/a22ca30698e6512fda71053b871da08846d27f32/internal/launcher/actions.go#L118). In other words, if this policy is disabled, only 1P MCPs are allowed. If it's enabled, when we check their MCP configuration for extra 3Ps to include.

The desired end state by Build will be this front end pieces being hooked up. Then Enterprise Admins can control whether to allow their Repo Admins to extend Padawan with 3P MCPs.

## Other relevant resources

- [Up-to-date demo video showing repository form](https://www.loom.com/share/60ac02dd1f2441c6a34b9a6fc9887f7a)
- [Demo video explaining config format, 1P/3P usage in depth](https://www.loom.com/share/ceb0337e0d8d4af2aaba21420659634c) **recorded before Repository settings form landed**
- [`README.md` in `sweagentd/mcp-client`](https://github.com/github/sweagentd/tree/main/mcp-client#mcp-client)
- Example config to test all the things

```
{
  "mcpServers": {
    "figma": {
      "type": "local",
      "command": "npx",
      "tools": ["*"],
      "args": [
        "-y",
        "figma-developer-mcp",
        "--figma-api-key=$FIGMA_KEY",
        "--stdio"
      ],
      "env": {
        "FIGMA_KEY": "COPILOT_MCP_FIGMA_KEY"
      }
    },
    "playwright": {
      "type": "local",
      "command": "npx",
      "args":["@playwright/mcp@v0.0.32"],
      "tools": ["browser_navigate"]
    }
    "fetch": {
      "type": "local",
      "command": "uvx",
      "args": ["mcp-server-fetch"],
      "tools": ["*"]
    },
    "time": {
      "command": "python",
      "args": ["-m", "mcp-server-time"],
      "tools": ["*"]
    },
    "sequentialthinking": {
      "command": "docker",
      "args": [
        "run",
        "--rm",
        "-i",
        "mcp/sequentialthinking"
      ],
      "tools": ["*"]
    }
  }
}
```
