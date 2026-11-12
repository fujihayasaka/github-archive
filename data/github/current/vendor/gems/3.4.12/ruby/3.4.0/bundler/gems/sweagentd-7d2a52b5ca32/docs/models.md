# Models

Padawan supports a few different model and agent backends. In the future we anticipate making a model picker available in org/repo settings. For now though this must be configured through issue labels.

## Issue Label Format

The model is currently configured by a label on the issue/PR. This label must be in the format:

```
copilot:agent=<agent-name>
```

## Support Agents in the Runtime

The agent-name includes up to two parts:

```
<provider>:<model>
```

The provider is one of these:

- `sweagent-capi` (default): Uses Copilot API
- `sweagent-aip`: Uses a private endpoint from the Azure AI Platform team (Not currently supported in production)
- `sweagent-anthropic`: Makes direct calls to Anthropic API (Not currently supported in production)
- `sweagent-openai`: Makes calls to Azure Open AI endpoints (Not currently supported in production)

This table includes a selection of available provider, models and options:

| Example                           | Description                                                                        |
| --------------------------------- | ---------------------------------------------------------------------------------- |
| `sweagent-capi`                   | Defaults to Sonnet 4 served by CAPI.                                             |
| `sweagent-capi:claude-sonnet-4`   | Sonnet 4 served by CAPI.                                                         |
| `sweagent-capi:claude-3.7-sonnet` | Sonnet 3.7 served by CAPI.                                                         |
| `sweagent-capi:oswe`              | OSWE model served by CAPI.                                                         |    |

A complete example looks like:

```
copilot:agent=sweagent-capi:oswe
```

## Required feature flags for changing models for a PR

By default, selecting a different model using the above issue label is disabled for all repositories (except sweagentd and ghcpd org for testing). 

To allow model selection, you need to opt yourself or the repo you want to in using the feature flag below.

[sweagentd_can_select_model](https://devportal.githubapp.com/feature-flags/sweagentd_can_select_model/targeting-rules?stamp=dotcom)

