# Tokens and Authorization in Actions

Copilot coding agent (CCA) uses a few different tokens and authorization methods to enable its Agent runtime to work within GitHub Actions. This document summarizes how these pieces come together to enable CCA's user experiences.

> **Note:** This document assumes you are familiar with the [overall architecture of the service](./architecture.md).

## The `copilot-swe-agent` GitHub App and CAPI proxy

A `copilot-swe-agent` GitHub App provides the primary way for the `sweagentd` service to generate access tokens to enable it and the Agent runtime to interact with GitHub. This app is installed on all repositories that have the `sweagentd` service enabled, and it is used to generate both server-to-server and user-to-server tokens.

**User-to-server** tokens generated using this App are also used to authenticate calls to endpoints for the Copilot API (CAPI). For each call, CAPI performs a first-pass authorization check that validates that the user in question has access to Copilot as a whole for the specified integration ID. See CAPI's documentation for details.

In addition `sweagentd` has a proxy endpoint in CAPI that allows other systems to interact with `sweagentd`'s unique capabilities. The production URL for this proxy is `https://api.githubcopilot.com/agents/swe` and any calls to paths under `/agents/swe` are automatically proxied to `sweagentd`.

e.g. `https://api.githubcopilot.com/agents/swe/agent/jobs` corresponds to [this endpoint](https://github.com/github/sweagentd/blob/25dcf726ab903d907ebe05b44ce745e7cc50498e/cmd/http/main.go#L237).

In addition to standard `Bearer` tokens, calls from the monolith can opt to use encrypted `GitHub-Bearer` tokens instead since sweagentd's CAPI proxy endpoint will automatically decrypt them and pass the underlying tokens to `sweagentd` ([see here for details](https://github.com/github/copilot-api/blob/6414ab77de3b01bdadc1793898af43e427f7d05b/pkg/agent/agentproxy/agentproxy.go#L61-L93)).

## Authorization for `sweagentd` endpoints

While this CAPI proxy performs the same types of authentication step as other parts of CAPI, a simple repo scoped token is insufficient in many cases. Let's cover what happens at these endpoints.

### `/agent`

Everything under `/agent` is intended as callbacks for the runtime or related cleanup steps in the actions workflow.

#### `/agent/jobs`

One of the core endpoints used by the agent runtime is the `/agent/jobs` endpoint. This endpoint allows the runtime to call back to the`sweagentd` service while running within Actions with both progress and results from the job it is currently executing within an Actions environment. While its intent is fine-grained, this endpoint does effectively result in new comments or update the body updates for the related PR.

One of the key things we therefore need to guard against is someone with a user-to-server token being able to modify information on an arbitrary job and by extension falsify information on the PR. While a `job_id`, `repo_id`, and `owner_id` are all required arguments, these three values are "guessable" either because they're a sequence or formatted using other information. They are inputs, not secrets.

One such check is to verify that the user corresponding to the user-to-server token **has access to the repository** that was passed into the request. However, this does **not** prevent someone from using a token from one repo that they have access to from modifying another job for this same or different repo.

##### Job nonce

To guard against cross-job updates, `sweagentd` generates a nonce when the job is created. This nonce is a random string that is unique to the job. Given a job's lifetime is one end-to-end execution of the agent runtime, this provides a simple, secondary, fine-grained authorization secret.

The nonce is passed as a value in the `X-GitHub-Job-Nonce` in addition to the user-to-server access token in the `Authorization` header and validated against the job database by doing a look up with the `job_id`, `repo_id`, and `owner_id` values passed in as inputs.

#### `/agent/cleanup`

The `/agent/cleanup` endpoint is exclusivley fired [via sweagentd's dynamic Actions workflow here](https://github.com/github/sweagentd/blob/d060c99bf3f7d1bd0f5931c7e966bfbf806cb362/internal/launcher/actions_workflow.yaml#L138-L145). It focuses on two things:

1. Revoking access to any tokens passed into a comma separated `X-GitHub-Copilot-Cleanup-List` header value
2. Logging a telemetry point indicating that an Actions run has completed (even if the job itself fail or the runtime bombed).

The request body includes the following that is used to look up the related job:

```json
{ "oid": <owner_id>, "rid": <repo_id>, "wid": <workflow_run_id> }
```

However, even if the job look up fails, the API will always revoke the tokens because this fundamentally reduces access rather than granting it. It does, however, log different telemetry data depending on whether the job specified was complete or not.

### The Job API (`/jobs`)

The Job API can create jobs and thus has a slightly different set of needs. To learn about authentication and authorization, see the [Job API ADR for more details](https://github.com/github/sweagentd/blob/main/docs/adr/0001-create-job-api.md).

## Tokens within Actions

Executing the runtime within Actions ultimately requires up to three separate tokens depending on the scenario to ensure security. Two `GITHUB_COPILOT_*` tokens are minted in the monolith using the `copilot-swe-agent` GitHub App. The other is the Actions workflow `${{ github.token }}` that is minted by Actions itself. The table below summarizes each token and their intended use.

| Token                                  | Used By                                                                               | Type / Scope                                                                                                             | Purpose                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| -------------------------------------- | ------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `GITHUB_COPILOT_API_TOKEN`             | Agent runtime (but kept back from the `bash` tool). Optionally the GitHub MCP server. | **User-to-server** token with a repository scope and **read** access to **contents**, **pull requests**, and **issues**. | Used to access with the Copilot API (CAPI) (and proxied `sweagentd` endpoints). It is also used as the default token for the GitHub MCP server if no other tokens are configured.                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| `GITHUB_COPILOT_GIT_TOKEN`             | Agent runtime (but not in `bash` tool's environment)                                    | **Server-to-server** with repo-scoped **contents and workflow write** access.                                            | This token is used by the runtime to push updates to the underlying git repository. It is currently server-to-server because this is the only way today to enable a confirmation button in the PR UX that allows the user to approve running other Actions CI/CD, checks, or other workflows. This approval is critical because of these workflow's access to secrets and the fact that something the agent did may have impacted what happens. In addition, Actions `${{ github.token }}` cannot be used because it cannot trigger workflow runs at all, and changes would be attributed to Actions instead of CCA. |
| `${{ github.token }}` / `GITHUB_TOKEN` | [Actions setup steps](https://gh.io/copilot/actions-setup-steps) (optional)           | **Server-to-server** minted by Actions instead of the `copilot-swe-agent` App.                                           | By default it has no permissions and is not used. It can be updated with the minimum scope permissions needed to perform any configured setup steps without impacting the runtime's ability to push changes.                                                                                                                                                                                                                                                                                                                                                                                                             |

### Token lifecycle

All three of these tokens are minted when a job is kicked off in Actions. They are provided as environment variables to certain processes (but not all) as defined in the [`actions_workflow.yaml` template](https://github.com/github/sweagentd/blob/main/internal/launcher/actions_workflow.yaml).

A final `if: always()` workflow that is responsible for cleaning up the tokens. This step will run even if the job fails or is cancelled, and calls the `/agent/cleanup` endpoint on `sweagentd` to revoke the `GITHUB_COPILOT_API_TOKEN` and `GITHUB_COPILOT_GIT_TOKEN`.

Action's own `${{ github.token }}` token is automatically cleaned up after the workflow run, so when combined with this cleanup step, all tokens are revoked by the time the Actions workflow is complete.
