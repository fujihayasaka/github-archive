# Custom Agents Specification

**Status:** accepted

**Deciders:** @josebalius @chuxel @belaltaher8

> **Note:** For additional context and the overall vision for Custom Agents, see [this document](https://docs.google.com/document/d/1MDns4w1F8NFxjawgDkk3fvgXDkuc6Ueb-dTZNNgJSBs/edit?usp=sharing). This spec doc focuses on what we have delivered so far.

## Custom Agent definition files

Custom Agents are defined in a markdown file with yaml-based frontmatter. In their simplest form, they are similar to [VS Code's chat mode](https://code.visualstudio.com/docs/copilot/customization/custom-chat-modes#_chat-mode-file-structure) or [Claude Codes's subagent configuration](https://docs.anthropic.com/en/docs/claude-code/sub-agents).

In their most basic form, this includes a `name`, `description`, and a list of `tools` that the custom agent can use. Our format will add to this and include areas like MCP config. To enable org / enterprise-level controls, some properties are also only allowed for custom agents defined at those levels (more later).

### Examples

Repo level custom agent with all tools enabled:

```text
---
name: my-custom-agent
description: Custom agent description here
---

...prompt..
```

Org level custom agent with specific tools enabled and a new MCP server with all tools enabled and a secret specified:

```text
---
name: my-custom-agent-with-mcp
description: Custom agent description here
tools: ['tool-a', 'tool-b']
mcp-servers:
  custom-mcp:
    type: 'local'
    command: 'some-command'
    args: ['--arg1', '--arg2']
    tools: ['tool-1', 'tool-2', 'tool-3']
    env:
      ENV_VAR_NAME: ${{ secrets.COPILOT_MCP_ENV_VAR_VALUE }}
---
...prompt..
```

### Definition file locations

Definition files end in `.md` can be placed in one of the following locations:

- **Repository level custom agents:** `.github/agents` folder in the repo.
- **Org level custom agents:** These agents are stored in the `<org>/.github` or `<org>/.github-private` repositories. Configuration files may be placed the `/agents` folder.
- **Enterprise level custom agents:** These agents are stored in a repository specified in the enterprise's settings in GitHub. Configuration files may be placed the `/agents` folder.

Having org/enterprise-level agents allows not only for sharing config across many repositories, but also allows for a PR-based workflow to be used for approving and updating them. As a result, there are some differences in capabilities between repo-level and org-level custom agents.

### YAML frontmatter and repo vs org-level properties

The following table outlines the properties that should be supported in repo-level vs org/enterprise-level custom agents.

For completeness, it also includes a column for "VS Code chat mode" config and Claude Code subagents to highlight which properties are currently supported by these tools and in some cases places where we may diverge.

| Property        | Type                                                                             | Purpose                                                                                                                                                                                                                                                                                                                                    | Repo      | Org / enterprise | VS Code              | Claude Code subagents            |
| --------------- | -------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | --------- | ---------------- | -------------------- | -------------------------------- |
| `name`          | string                                                                           | Unique display name for the custom agent. Defaults to filename without `.md`.                                                                                                                                                                                                                                                              | X         | X                | X (Planned)          | X                                |
| `description`   | **Required** string                                                              | Description of the custom agent's purpose                                                                                                                                                                                                                                                                                                  | X         | X                | X                    | X                                |
| `tools`         | list of strings, string                                                          | List of tool names the custom agent can use. Supports both a comma separated string and yaml string array. If unset, defaults to all tools.                                                                                                                                                                                                | X         | X                | X                    | X<br /> (comma separated string) |
| `argument-hint` | string                                                                           | Placeholder text to hint to the user what information should be entered for the agent.                                                                                                                                                                                                                                                     | (Planned) | (Planned)        | X                    | X (slash commands)               |
| `target`        | `vscode`, `github-copilot`, or omitted/empty (works everywhere/no restrictions). | Indicates agent is only expected to work in a specific place (usually due to tools). Clients (dotcom, mobile, editors) can pay attention to this property provide hints or warn/error as appropriate. While target value can be optionally passed into the list API to tailor results, creating a CCA job is not blocked by this property. | X         | X                | X                    |                                  |
| `metadata`      | map of name-value string pairs                                                   | Arbitrary key/value metadata that can be attached for use by telemetry and in clients.                                                                                                                                                                                                                                                     | X         | X                | (Likely to be added) |                                  |
| `infer`         | bool                                                                             | Boolean indicating whether this custom agent can be executed as a tool.                                                                                                                                                                                                                                                                    | X         | X                | (Likely to be added) |                                  |
| `mcp-servers`   | object                                                                           | Additional MCP servers and tools that should be used by the custom agent. See below for details.                                                                                                                                                                                                                                           |           | X                | ?                    |                                  |
| `model`         | string                                                                           | Model to use.                                                                                                                                                                                                                                                                                                                              |           |                  | X                    | X                                |
| `handoffs`      | object                                                                           | Configuration that indicates what the next steps should be.                                                                                                                                                                                                                                                                                |           |                  | X                    |                                  |

> **Note:** The `model` and `handoffs` properties are **not supported by CCA** at this time.
#### `mcp-servers` property details

The `mcp-servers` property is a yaml representation of the MCP json content. However, there are a few updates we want to make to improve interoperability and ease of use.

Most sub-properties are the same as the json representation for Copilot Coding Agent configuration. This section will call out changes from the initial implementation of MCP config in Copilot coding agent that are relevant to custom agents.

##### MCP Server `type`

For compatibility, the `stdio` type used by Claude Code and VS Code is mapped to CCA's `local` type.

##### MCP Server environment variables and secrets

Custom agent MCP config supports the same env / secret replacement capabilities as existing repo-level MCP configurations. Like in repository-level config, secrets/vars can come from same "copilot" environment in the repository's settings. The way these are referenced has expended to cover common syntax in GitHub Actions and Claude Code.

In both json config and this yaml file:

- `COPILOT_MCP_ENV_VAR_VALUE` for `env` only - generally not recommended given header differs
- `$COPILOT_MCP_ENV_VAR_VALUE` for `env` and `header`
- `${COPILOT_MCP_ENV_VAR_VALUE}` for `env` and `header`

In this yaml frontmatter:

- `${{ secrets.COPILOT_MCP_ENV_VAR_VALUE }}` for `env` and `header`
- `${{ vars.COPILOT_MCP_ENV_VAR_VALUE }}` for `env` and `header` (similar to [Claude Code](https://docs.claude.com/en/docs/claude-code/mcp#environment-variable-expansion-in-mcp-json))

#### Tool names and aliases

To be "cut-and-paste" compatible with VS Code chat modes and Claude Code subagents, we support common names for primary tools along with some compatibility aliases. We also support a "namespacing" pattern to avoid tool naming conflicts across products and MCP servers. Specifically:

- Tool names that originate from a specific MCP server can be prefixed with the name of the server followed by a `/`. e.g. `some-mcp-server/some-tool`
  - Tools that are specific to MCP servers originating from VS Code extensions can be prefixed with the extension name as a proxy for the server name. e.g. `azure.some-extension/some-tool`
- You can indicate that all tools from a specific MCP server should be enabled through a `*` wildcard. e.g. `some-mcp-server/*`.
- You can specify `*` by itself to enable all tools. e.g. `tools: ["*"]`
  - However, this is optional. Omitting the tools property entirely will also enable all tools.
- All unrecognized tool names are **ignored**. This allows both VS Code and Copilot coding agent / CLI specific tools to be specified in the same config as needed without causing problems.
- A set of "tool aliases" are available that map to product specific tools (see below).

> Note: VS Code and Copilot out-of-box named tools should not conflict with one another. The same tool name should always have the same meaning or be ignored in one or the other product. If needed, we could add product specific namespaces like "vscode/\*", but this does not appear to be required.

#### Planned tool aliases

In general, we want to try to keep Copilot coding agent and VS Code in sync as much as we can and opportunistically support those [defined by Claude Code](https://docs.claude.com/en/docs/claude-code/settings#tools-available-to-claude) as well.

**All aliases are case insensitive.** Compatibility aliases are capitalized to match the origin of the alias, not to imply case sensitivity.

| Primary alias | Compatibility Aliases                        | CCA mapping                                          | Purpose / Notes                                                                                                                                       |
| ------------- | -------------------------------------------- | ---------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| `execute`     | `Bash`, `powershell`, `shell`                | Shell tools: `bash` or `powershell`                  | Execute a command in the appropriate shell for the operating system.                                                                                  |
| `read`        | `Read`, `NotebookRead`                       | `view`                                               | Read file contents.                                                                                                                                   |
| `edit`        | `Edit`, `MultiEdit`, `Write`, `NotebookEdit` | Edit tools: e.g. `str_replace`, `str_replace_editor` | Allow LLM to edit . Exact arguments can vary.                                                                                                         |
| `search`      | `Grep`, `Glob`                               | `search`                                             | Search for files or text in files.                                                                                                                    |
| `agent`       | `Task`, `custom-agent`                       | "Custom agent" tools                                 | Allows a different custom agent to be invoked to accomplish a task. Claude Code uses "Task" for triggering subagents which is close to the same idea. |
| `web`         | `WebSearch`, `WebFetch`                      | Currently N/A for CCA. Closest is bash + curl.       | Allows fetching content from URLs and performing a web search                                                                                         |
| `todo`        | `TodoWrite`                                  | Currently N/A for CCA.                               | Creates and manages structured task lists. Not supported in CCA today, but will be by VS Code.                                                        |

#### Tool names for "out-of-box" MCP servers

The following MCP servers are available out-of-box for Copilot coding agent and can be referenced using namespacing.

| MCP server name | Available tools                                                                                                                                                                                                                                                                                                                                                                                                           |
| --------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `github`        | All [read-only tools](https://github.com/github/github-mcp-server?tab=readme-ov-file#read-only-mode) are available by default, but the token the server receives is scoped to the source repository. `github/*` includes all of them, or you can reference `github/<tool name>` where `<tool name>` is a value from the [MCP server documentation](https://github.com/github/github-mcp-server?tab=readme-ov-file#tools). |
| `playwright`    | All playwright tools are available by default, but the server runs is configured to only access localhost. `playwright/*` includes all of them, or you can reference `playwright/<tool name>` where `<tool name>` is a value from the [MCP server documentation](https://github.com/microsoft/playwright-mcp?tab=readme-ov-file#tools). By default the token it has access to is scoped to the source code repository.    |

Other MCP servers like "blackbird" may be running as well, but are not things we'd document for external customers.

### Versioning

The file format for custom agents does not have explicit support for specifying a version in the file. Instead, the version is implicitly defined by the git commit SHA that the file is read from. This allows users to create branches or tags with different versions of custom agents as needed. Endpoints are then updated to allow specifying a SHA (with a branch or tag name likely being options in the future). More on the endpoints next.

## Custom agent config endpoints

To allow user experiences to find a list of custom agents available for a given repository, we will add a new `/custom-agent` endpoint to `sweagentd` which currently translates to `https://api.githubcopilot.com/agents/swe/custom-agents` in prod. Authentication and authorization will be handled by `sweagentd` with help from existing monolith twirp endpoints for validating access and the access token required `read` / `pull` / `repo` rights to the related repositories. More information will be described in the following sections.

### `GET /custom-agents/{repoOwner}/{repoName}[?target=github-copilot|vscode][&exclude_invalid_config=true|false][&dedupe=true|false][&include_sources=repo,org,enterprise]`

Returns a list of custom agents available for the given repository. This includes both repo-level and org/enterprise-level custom agents. The response is intended to just be enough to populate a selection UI and, optionally, go get additional details like the custom agent's prompt.

By default, custom agents with invalid configuration (e.g. yaml parsing errors) are included in the response with a `config_error` property describing the issue, and whatever was successfully parsed is also presented. This allows clients to see that an agent exists, but also know that it cannot be used until fixed. However, the optional `exclude_invalid_config` query parameter can be used to exclude these invalid configurations from the response.

The `include_sources` query parameter can be used to specify the agent source repos that should be used to create the list. It is a comma separated string that can include any combination of `repo`, `org`, and `enterprise`. If not specified, all three sources are included.

The optional `dedupe` query parameter can be used to indicate whether duplicate custom agents (same name from different sources) should be deduplicated. If `true`, the closest source to the repository is used (repo > org > enterprise). If `false`, all custom agents are returned. The default is `true`.

The `target` query parameter can be used to either affect filtering or `config_error` values (if `exclude_invalid_config=false`) based on the specified target environment.

Currently the API defaults to `target=github-copilot`, but this will be updated in the future to return all agents if not specified. You should therefore include the target parameter in your requests. Additional targets may be added in the future.

Example response:

```jsonc
{ "agents":
  [
    {
      "name": "my-custom-agent",
      "repo_owner_id": 123456,
      "repo_owner": "owner",
      "repo_id": 234567,
      "repo_name": "repo",
      "display_name": "My Custom Agent",
      "description": "Custom agent description here",
      "tools": ["*"],
      "argument_hint": "Optional hint text here",   // optional
      "metadata": {                                 // optional
        "key1": "value1",
        "key2": "value2"
      },
      "version": "40-character-sha-goes-here"
    },
    {
      "name": "my-custom-org-agent-with-mcp",
      "repo_owner_id": 123456,
      "repo_owner": "owner",
      "repo_id": 234567,
      "repo_name": "repo",
      "display_name": "My Custom Agent with MCP",
      "description": "Custom agent description here",
      "tools": ["bash", "edit", "mcp-server1/tool-1", "mcp-server1/tool-2", "mcp-server2/*"],
      "version": "40-character-sha-goes-here",
      "mcp_servers": { ... }  // optional, same contents as CCA's repo config.
    },
    {
      "name": "agent-with-config-error",
      "repo_owner_id": 345678,
      "repo_owner": "org-name",
      "repo_id": 456789,
      "repo_name": "some-repo",
      "display_name": "Org Level Agent",
      "description": "",
      "tools": [],
      "version": "40-character-sha-goes-here",
      "config_error": "error parsing custom agent configuration: ...error details..."  // optional
    },
    {
      "name": "vscode-only-agent",
      "repo_owner_id": 123456,
      "repo_owner": "owner",
      "repo_id": 234567,
      "repo_name": "repo",
      "display_name": "VS Code API Caller",
      "description": "Custom agent description here",
      "tools": ["vscodeAPI", "extensions"],
      "version": "40-character-sha-goes-here",
      "target": "vscode", // optional
      "config_error": "agent configuration cannot be used because the 'target' field is set to 'vscode'" // optional
    },
  ]
}
```

Note that in this case, `tools` is a string array that is always populated. If all tools are enabled, `["*"]` will be returned. If no tools are enabled, `[]` is returned. The `tools` will **not** be omitted or return nil/null.

> Note: The reason the owner and repository name are returned is that custom agents defined at the org or enterprise level will come from different repositories.

To keep things simple, the list endpoint can uses the latest commit SHA for the source branch get the related version for each custom agent. This value is both the easiest for users in GitHub and for systems to find.

### `GET /custom-agents/{repoOwner}/{repoName}/{customAgentName}[?version=...]`

Returns a json representation of yaml configuration described above with the "prompt" in a `prompt` property. This is intended to be used by the client to fetch the full custom agent configuration after a user has selected one. Unpopulated properties should be omitted.

The optional `version` query parameter can be used to specify a git ref (branch, tag, or commit SHA) to fetch the custom agent definition from. If not specified, the default branch should be used.

For example:

```jsonc
{
  "name": "my-custom-agent",
  "repo_owner_id": 123456,
  "repo_owner": "owner",
  "repo_id": 234567,
  "repo_name": "repo",
  "display_name": "My Custom Agent with MCP",
  "description": "Custom agent description here",
  "tools": ["*"],
  "version": "40-character-sha-goes-here",
  "mcp_servers": { ... },  // optional, only if MCP servers are defined. Contents are the same as CCA's repo config.
  "argument_hint": "Optional hint text here",   // optional
  "metadata": {                                 // optional
    "key1": "value1",
    "key2": "value2"
  },
  "prompt": "...prompt..",

}
```

## Processing

Processing the contents then breaks out as follows:

### Prompt

For this phase of the implementation, we are only supporting user prompt updates with custom agents. Therefore, the prompt should be appended to the problem statement / user prompt before being passed to the LLM.

### Tools

The `tools` list filters the set of tools that are made available to the agent - whether builtin or sourced from MCP servers.

To avoid supporting `nil` with special meaning, "all tools" is persisted and transmitted using the array `["*"]` to make this explicit, while `[]` is used to represent tools. APIs like the twirp and Job API should also follow this behavior.

However, since it is hand edited, `tools` can be omitted from the top-level the yaml frontmatter in definition files and is automatically mapped to `["*"]` internally. (However, note that `tools` is still a required field for MCP config under the `mcp-server` property in this same frontmatter.)

### MCP config

The order that MCP config should be processed is as follows:

1. Out-of-box MCP config (e.g. GH MCP)
2. Custom Agent MCP config
3. Repo-level MCP config

This ensures that the appropriate levels are able to override behaviors where appropriate.

## Custom agent support in the `/agent` endpoint

The runtime agent callback (`/agent`) also includes support for custom agents to allow the public endpoints above to version independently from the what the runtime uses.

> Note that the `/agent` endpoint is **only** for the Copilot coding agent runtime and should not be used in other cases.

Specifically:

- An `/agent/jobs/{jobId}` endpoint returns core job details along with a complete list of available custom agents for the specified job.
- An `/agent/custom-agents/{ownerName}/{repoName}/{agentName}` endpoint mirrors the functionality of the `/custom-agents/{ownerName}/{repoName}/{agentName}` endpoint described above.
