# Plugins in CCA (Repo, Org, & Enterprise Level)

Status: accepted

Deciders: @belaltaher8 @arthurnn @copilot-cli-team @agent-platform-team

Related issue: https://github.com/github/sweagentd/issues/10666, https://github.com/github/sweagentd/issues/10646, [copilot-agent-runtime#4743](https://github.com/github/copilot-agent-runtime/issues/4743)

## Context

### Current status

#### What is a Plugin?

Plugins are a way to group various AI assets together (e.g. custom agents, hooks, skills, mcp, lsp servers, commands etc). They are essentially repositories that contain the previously mentioned AI assets at specific directories so that consumers know where to look for them. Plugins can live at the root of a repository, in a subdirectory of a repository, or in a marketplace. 

A marketplace is a repository which defines a `marketplace.json`. This file specifies the metadata for the marketplace this repository represents and information regarding the plugins in this marketplace. Plugin manifests can be located inline in the marketplace config, in the same repository as the marketplace, or even in an external repository. An example is [`github/copilot-plugins`](https://github.com/github/copilot-plugins). In a marketplace's source repo, there will be a `marketplace.json`. 

Plugins can be manually or automatically installed. Installing a plugin just means providing all the AI assets associated with that plugin for agent invocation. Plugins that are automatically installed are specified through the `enabledPlugins` field on a `.github/copilot/settings.json` or `.claude/settings.json`. See an example of this below: 

In a `.github/copilot/settings.json` or `.claude/settings.json`

```jsonc
{
  "enabledPlugins": {
    "sentry@copilot-plugins": true,
    "myorg/internal-tools": true,
    "datadog@copilot-plugins": false
  }
}
```

Below outlines the different syntax supported for defining plugins under the `enabledPlugins` field: 

| Format | Example | Type | Meaning |
|--------|---------|------|---------|
| `plugin@marketplace` | `sentry@copilot-plugins` | **marketplace** | Look up `sentry` in the `copilot-plugins` marketplace |
| `owner/repo` | `github/my-plugin` | **github** | Clone directly from `github.com/github/my-plugin` |
| `owner/repo:path` | `myorg/monorepo:plugins/sentry` | **github** | Clone repo, use subpath |
| `owner/repo@<sha>` | `github/my-plugin@abc...01` | **github** | Clone directly from `github.com/github/my-plugin` pinned to commit SHA |
| `owner/repo:path@<sha>` | `myorg/monorepo:plugins/sentry@abc...01` | **github** | Clone repo pinned to commit SHA, use subpath |
| `url:https://...` | `url:https://example.com/plugin.git` | **url** | Clone from URL |
| `./path` or `/path` | `./local-plugin` | **local** | Local filesystem path |

The `@<sha>` SHA-pin suffix is only valid on `owner/repo` and `owner/repo:path` direct-repo forms. The right-hand side must be a full commit SHA (40 chars for SHA1 or 64 chars for SHA256); branch/tag refs and short SHAs are rejected. Marketplace plugins (`plugin@marketplace`) are not pinned via this syntax — their pinning happens at the marketplace layer (the marketplace's own `ref` in `extraKnownMarketplaces`, and per-plugin `ref` in `marketplace.json`). URL specs (`url:https://...`) do not support SHA pinning: users who want to pin a GitHub-hosted plugin to a commit should use the native `owner/repo@<sha>` (or `owner/repo:path@<sha>`) form instead, which can express the same target.

A user can specify new marketplaces under the `extraKnownMarketplaces` field in a `settings.json`. Below outlines the different kinds of sources users can specify in `extraKnownMarketplaces`

 | `source` | Required fields | Optional fields | Example |
 |----|----|----|----|
 | `"github"` | `repo` (`owner/repo`) | `ref` | `{"source": "github", "repo": "myorg/my-marketplace", "ref": "main"}` |
 | `"git"` | `url` (full git URL) | `ref` | `{"source": "git", "url": "https://github.com/myorg/my-marketplace.git", "ref": "main"}` |
 | `"directory"` | `path` | — | `{"source": "directory", "path": "/local/path"}` |

Below outlines the syntax around how plugins are sourced in `marketplace.json` files:

 | Form | `source` value | Required fields | Optional fields | Example | Meaning |
 |------|---------------|----------------|-----------------|---------|---------|
 | Object | `"github"` | `repo` (`owner/repo`) | `ref`, `path` | `{"source": "github", "repo": "myorg/my-plugin"}` | Clone from `github.com/myorg/my-plugin`; `path` is subdir within that repo |
 | Object | `"url"` | `url` | `ref`, `path` | `{"source": "url", "url": "https://example.com/plugin.git"}` | Clone from arbitrary URL; `path` is subdir |
 | Plain string | *(any relative path)* | — | — | `"./plugins/my-plugin"` | Path relative to the marketplace repo itself (same clone, different subdir) |


#### What Plugin support do we have today?

##### Copilot CLI

Copilot CLI supports both installing plugins manually through `copilot plugin install SPECIFICATION` and automatically through the `enabledPlugins` field. **The CLI uses `git clone` which leaves it up to the user to configure a token with appropriate permissions to clone plugins**. For more information on plugins in Copilot CLI refer to our [reference doc](https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-plugin-reference), our [installation guide](https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/plugins-finding-installing), and the [About Plugins](https://docs.github.com/en/copilot/concepts/agents/copilot-cli/about-cli-plugins) page. The CLI supports `github/copilot-plugins` & `github/awesome-copilot` as default plugin marketplaces.

##### VSCode

VSCode also currently supports plugins. The behavior of VSCode is similar to Copilot CLI. For more information on plugins in VSCode, refer to [Agent Plugins in VSCode](https://code.visualstudio.com/docs/copilot/customization/agent-plugins).

#### AI assets supported in CCA

CCA does not currently have support for plugins and lacks support for certain constituent AI assets (e.g. `hooks`, `lspServers`, `mcp.json`). CCA currently does support `commands`, `agents`, and `skills`. CCA has its own mechanism for MCPs through repository settings and custom agents. Consolidating that to support `mcp.json` is out of scope for this document.

`agents` currently have organization and enterprise level support. Admins can configure agents in their `.github`/`.github-private` repositories and easily distribute them across an organization. Enterprise controls also exist for those admins to designate a certain organization's `.github-private` repository to be used as a source to distribute their agents across an enterprise.

#### SDK Migration in CCAv3

There is currently work being done to migrate CCA's agent runtime to be on the `copilot-engine-sdk` & `copilot-sdk`. Migrating to the `copilot-sdk` will make it much easier to build support in CCA for `hooks` / `lspServers` and plugins in general since we will be able to leverage existing code instead of rebuilding it ad-hoc in CCA's current implementation. 

#### Agentic Apps as Plugins

We are also planning to build the ability to distribute plugins as GitHub Apps. This would include first-class identity support through our existing apps infrastructure and allow users to @-mention installed plugins when sending tasks to Copilot Coding Agent. To read more about this, refer to this [document](https://microsoft-my.sharepoint.com/:w:/p/arneves/IQDUPZ40IOrRQpXSJiAkfpRPATQFHJf9ZxqfrWy0c5ycTrA?e=VaBJQZ). A notable addition to the spec in the linked document is the ability to specify a main agent in a plugin configuration.

### Requirements

- We achieve a way to enable organizations to centrally distribute plugins and their constituent assets to Copilot CLI & CCA users without requiring each user to configure them individually
- Our solution takes into consideration that, with plugins, the number of AI assets required to load can quickly skyrocket
- Our solution properly considers the security implications of solving for an agent needing to access AI resources that may be sourced from a private repository
- Our plugin solution offers a cohesive story that takes into account all surfaces that plugins apply to on Copilot Coding Agent

## Decision

### Plugins will depend on CCAv3

In order to holistically support plugins in CCA, we will need to build support for `hooks` & `lspServers`. Instead of doing that ad-hoc, it makes more sense to do this in parallel with the CCAv3 migration. A consequence is that shipping plugin support for CCA will depend on shipping CCAv3. That work is currently targeting shipment by the end of April 2026. Support for plugins can be worked on in parallel.

#### Alternatives considered

- **Implementing `hooks` & `lspServers` ad hoc to CCAv2**: This is an option but seems like a wasted effort given we'll need to port the functionality over to CCAv3 anyways. The implementation in CCAv3 is also more straightforward given its use of the `copilot-sdk`

### We will clone the plugin source repo to disk.

In order to closely match the architecture of the CLI & VSCode, we will also clone plugin source repositories to disk in CCA. Both of these clients rely on the user's locally set token for cloning. We can't do this in CCA since the agent works on a VM in the cloud. For public repos, things work fine since no authentication is required. But for private repos, we need to provide a token. Luckily, the service layer already has a twirp call that we can use to mint U2S tokens. We will leverage this functionality to generate the tokens required to clone all the plugin contents to disk. These tokens must be minted with the minimum permissions required for cloning, should be read-only, must be restricted to an allowlist of the specific plugin source repositories being resolved for the current run, and must have the shortest feasible TTL.

We will pass these tokens down to the actions workflow **in the `env` of a different step than the one our agent works in**. Basically, a similar pattern to how we provide user provided MCP sets to our out of process MCP client today. This way the agent will have access to the plugin source contents, which will be cloned already when the agent starts work, but the agent won't easily have access to the tokens. After the plugin contents are on disk, we can leverage the existing plugin loading functionality that the CLI uses. The token will not be persisted in any other way.

For marketplace resolution, we will mimic the CLI and support `extraKnownMarketplaces` if users want to specify marketplaces beyond the defaults. We will not support marketplaces sourced from `directory` in `extraKnownMarketplaces` since we aren't on a user's local machine.

#### Alternatives considered

- **CCA extracts AI assets from plugins at the service layer** - This approach was considered as a token-less one. We wouldn't have to pass a token down since the service layer would do all the work to extract the AI assets from the plugins specified and just pass a list of all the `agents`, `skills`, `hooks`, etc to the runtime. We decided against this because it was a big divergence from the way the CLI does things, and part of the spirit behind the CCAv3 work is to share more components and functionality between CCA and CLI.
- **CCA streams the AI assets directly into a .tar that we send to the runtime** - This approach was considered as another token-less one. This would involve leveraging spokes to stream all relevant files out of a plugin (i.e. the configuration files for the constituent AI assets in the plugin), bundle those up in a `.tar` and send it down to the runtime. This was an in-between approach where we still allowed the runtime to be the one to build the AI assets while not minting any tokens. However, given the additional complexity that would be required at the service layer, we decided against this.

### At first, we will just ship support for plugins sourced from public repositories on GitHub.com (CCA)

In order to expedite shipping plugin support for CCA, we will just support plugins sourced from public repositories at first. This will be our target for April 2026. And in May 2026, we will work on supporting plugins sourced from private repositories. This allows us to focus on just plugin functionality and not have to worry about the security considerations around minting tokens. The only token used for v1 of plugin support will be the one the agent already has for GitHub.com access. Since this is the only token the agent has, plugins must be sourced from GitHub.com. The CLI and VSCode rely on user provided tokens for auth when cloning plugin source, so they don't have this limitation.

### Organizations and Enterprises will have a `copilot/settings.json`

Following the same conventions that we have already established for custom agents, organization & enterprise admins will configure a `copilot/settings.json` that will include `enabledPlugins` & `extraKnownMarketplaces` fields in their `.github`/`.github-private` repositories. This will exactly mimic the syntax of the plugin related fields in a `.github/copilot/settings.json` at the repo level. 

#### Alternatives considered

- **Plugins themselves live in the `.github`/`.github-private` repository**: This could prove cumbersome to manage. Just providing a configuration file makes it much easier for admins to easily distribute and manage plugins.

### Service endpoint `plugins/{owner}/{repo}`

We will create an endpoint on `https://api.githubcopilot.com/agents/swe/plugins/{repo_owner}/{repo_name}`. This endpoint will include similar URL params as our existing custom agent service such as `include_sources` and `dedupe`. It will return a JSON representing the `enabledPlugins` & `extraKnownMarketplaces` configuration. An example response would be: 

```jsonc
{
   "enabledPlugins": {
      "sentry@copilot-plugins": true,
      "myorg/internal-tools": true,
      "belalsplugin@my-marketplace": true
   },
   "extraKnownMarketplaces": {
      "my-marketplace": {
         "source": {
            "source": "github",
            "repo": "belaltaher8/test-marketplace",
            "ref": "main"
          }
      },
      "git-marketplace": {
         "source": {
            "source": "git",
            "url": "https://github.com/belaltaher8/test-marketplace-git.git",
            "ref": "main"
          }
      }
   }
}
```

#### Alternatives considered

- **Endpoint returns the AI assets, not the configuration**: This would force clients to depend on our service layer implementation of extracting assets from plugins. By just providing the configuration, we allow clients to own their own organization / enterprise implementation story. 

### What about @-mentions? (a.k.a Agentic Plugin Apps)

When a user @-mentions a specific plugin in their task, we will include that plugin's AI assets in the sandbox. Agentic Plugin Apps are pinned to a SHA so we will have to clone the source accordingly. Applying the AI assets from the source will follow the same logic.

- The mentioned plugin is included when we're building our `reposToClone` at the service layer and so the runtime will be aware of the required source contents
- Agentic Plugin Apps can specify a primary agent for the task. We will leverage `job.CustomAgent` on the job DTO to enforce this.
- Other available AI assets either through plugins or existing inference capabilities remain available for inference as tools

@-mentioning multiple plugins is a future consideration but is out of scope for this document. If multiple plugins are mentioned, we will select the first.

### Future Considerations

- **Audit and visibility** - Admins should be able to see which plugins are enabled across their org/enterprise and audit their usage. Should we consider adding an audit log event, or does commit history suffice?
- **Multiple Agentic Plugin Apps** - If we just need to add the AI assets from each plugin, it should be easily scalable across multiple apps as long as we have the individual protos for each app. An open question is which app's primary agent will be used if multiple are specified.
- **Supporting `mcp.json` from plugins** - CCA has its own way of loading MCPs between its repository settings and custom agents. This needs to be carefully consolidated with `mcp.json` to not break existing flows. This was out of scope for this document but something we should consider in the future.
- **Plugins sourced from non-GitHub sources** - CCA just has a GitHub token and we can only mint GitHub tokens for it, so it's limited to just cloning plugin sources from GitHub.com. We could allow users to supply CCA with a token to clone from non-GitHub sources, but this is a future consideration.
