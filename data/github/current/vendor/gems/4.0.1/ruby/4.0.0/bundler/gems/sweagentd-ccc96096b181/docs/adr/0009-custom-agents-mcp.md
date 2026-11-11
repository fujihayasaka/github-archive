# Allowing MCP Configuration in Repository-Level Custom Agents

**Status:** accepted

**Deciders:** @belaltaher8 @chuxel

**Related issue:** [#8016](https://github.com/github/sweagentd/issues/8016)

## Current state of MCP Config in Custom Agents
Today, we only respect the MCP configuration of Custom Agents [that are set at the Org or Enterprise level](https://docs.github.com/en/copilot/how-tos/use-copilot-agents/coding-agent/create-custom-agents#configuring-an-agent-profile). We did this in order to align with our current permissions structure around MCP. For regular CCA runs, MCP servers must be set in the Repository Settings (i.e. only Admins can affect it). Only allowing Custom Agents at the Org+ level to specify servers was to adhere to our own security posture around the idea that MCP servers have to be set by a person with special privileges or in a privileged location. 

However, customers have expressed interest in having this requirement eased. Especially now with MCP being bundled in to other features like Custom Agents. For more information, refer to the [Custom Agents ADR/Spec here](./0005-custom-agents.md).

## Proposed State

### Requirements
- Custom Agents at the Repository level can specify MCP servers

### Alternatives considered
- **Move all MCP configuration for CCA to the repository level:** This would be accomplished through an `mcp.json` in a specific directory. This would lead to a more consistent product story because all MCP configuration for CCA could be done by anyone who can push to the repository. However, we realized we would be losing config validation before runtime with our MCP UX moving from a Settings page to a file. We could implement a UX similar to actions workflow files that helps users get syntax right, but that's non-trivial work. The many tendrils we identified from digging deeper into this solution convinced us to keep the scope of this change to just Custom Agents.

- **Maintain the existing restriction:** Keep MCP configuration limited to Custom Agents defined at the Org or Enterprise level, continuing to ignore MCP configuration specified by repository-level Custom Agents. This would have preserved the strictest interpretation of our current security posture but would not address strong customer demand or unlock the workflows that depend on repository-level configuration. 

### Decision
**We are going to be allowing MCP configuration for Custom Agents specified at the repository level.** 

When we designed this, we wanted to prioritize keeping a more consistent security posture. Now that we're more aware of what kinds of workflows folks could use MCP for & have lots of customers expressing interest, we're going to change this design. Everything else about our MCP design is remaining the same. We will now respect MCP servers for all Custom Agent configurations instead of throwing non-privileged ones out. We already have a feature flag `copilot_swe_agent_custom_agent_privileged_repo` gating this behavior.

Although one could argue it'll lead to a strange product experience having CCA's MCP servers specified through Repository Settings that only Admins can control while anyone who can commit to a repo can specify MCPs through a Custom Agent, we will be adding disclaimer texts under the Custom Agent policy controls to inform admins this is possible.

### Implications

#### Pros
- Customers have been asking for this
- Will enable workflows that weren't previously possible through Custom Agents

#### Cons
- We'll need to make clear to admins there's a way for non-admin to set MCPs more easily with Custom Agents enabled

#### Other considerations
- We'll need to revisit our Custom Agents docs
- In the future, we could create a dedicated UI section for MCP Secrets/Vars rather than using `copilot` environment. This has been something we've talked about for a while and know we want. There's currently [work underway](https://github.com/github/actions-dispatch/issues/353) to move away from the `copilot` environment toward a more dedicated configuration surface for secrets and variables.
