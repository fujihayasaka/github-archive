# Jobs API for Copilot Clients

Status: Partially implemented

## Context

As we're evolving Copilot coding agent (CCA), it is becoming clear that we want to be able to allow clients like VS Code to queue up jobs for processing that originate from things other than issues. Furthermore, individual developers may want to fire off arbitrary tasks that are not directly tied to planned work or may be picked up by the developer to continue on. While aspects of this can already be done with Agent mode in VS Code we want users to be able to queue up work from any number of services and delegate it to Copilot coding agent for processing while they do other processing.

With that in mind, this ADR describes a non-public Copilot API capability off of the existing `/agents/swe` endpoint to queue up jobs for processing tied to arbitrary tasks in addition to existing issues.

> **Note:** This ADR will assume that the pull request still ends up being the primary "entity" that is used to track progress and collaborate with the AI and loop in others into the conversation as appropriate. However, we do recognize that there's likely a need for a variation of a PR here that is more of general "task" tied to a specific user that would not clutter the main PR list. This ADR assumes that we will evolve the existing concept to support these kinds of interactions and improve the overall PR experience here. Even for scenarios where the PR UX may not be primary, the underlying PR data structure would be used.
>
> If for some reason we decide to not use the PR data structure, a separate ADR would be needed to understand how all of the existing capabilities PRs provide that Copilot coding agent uses would be replicated in a new data structure.

## Job API vs Session API

TLDR:

- **Job API** = queue up / stop async agentic work in CCA. For GH/MS use only.
- **[Session API](https://github.com/github/copilot-api/blob/main/docs/api/session.md)** = get a running view of executing agentic work.

The Job API endpoints are and **not** intended to replace or wrap the session API, but rather focus in on allowing clients to queue up asynchronous, cloud hosted, agentic workflows from multiple client surfaces. The session API is intended to be used as a general way to encapsulate information about an agentic workflow - whether cloud or not - in both a detailed and summary form. A session ID is returned by the job API.

While the API is technically publicly accessible given it is intended for client use (e.g. VS Code), it is considered a lower level "internal" API for GitHub / Microsoft use only. Over time we want to support multiple ways for queuing up work. At that point we'll have a different endpoint that proxies to the appropriate API based on the scenario - with the job API providing one of them. Since the session API **is** intended for public use, it is a strong candidate for that proxying endpoint.

### Example scenarios

This is a broad topic, so here are some example scenarios we'd like to enable over time.

#### New PR scenarios

1. Create a PR using a task description from the New PR experience in GitHub (w/o an issue)
1. Create a new PR using a task description from VS Code
   1. As an option in the GitHub PR extension
   1. Via chat surfaces (with the task containing summarized chat context)
   1. Transition from a VS Code Agent Mode session to an new PR (e.g. "Ok, this looks pretty good - can you create a PR and polish it up for me async?")
1. Support "+ New" button on the Sessions page that kicks off a new PR/session using a prompt (and repo/branch + in the future tools/model)
1. Enable dependabot (packages and language version auto-upgrades), and agentic Autofix features without having to couple to the issues or `sweagentd` Hydro handlers ([see here](https://github.com/github/code-scanning/blob/fd65986761b0dba4b4f1d1a6f1a3d361adea8d01/docs/adrs/0087-autofix-padawan-integration.md)).

#### Existing PR scenarios

1. Assign a task to Copilot coding agent tied to code for a locally checked out PR in VS Code - either created by a human, or even originally created by Copilot coding agent. e.g.
   1. Chat surfaces (with the task containing summarized chat context)
   1. Transition back from VS Code Agent Mode session on a locally opened PR (e.g. "Ok, this looks pretty good - can you polish it up for me async?")
1. Supporting a "fix merge conflict" button on an existing PR - whether created by a human and not assigned to Copilot coding agent.
   1. In GitHub
   1. In VS Code - e.g., when you try to pull from main and it fails
1. Support an agentic Copilot Code Review feature in the future (where it doesn't push changes but presents them as suggestions)
1. Kick off multiple tasks / jobs concurrently for the same PR.

#### Other scenarios

1. Display a list of jobs with different groupings and their macro-level state in UX other than GitHub.com (e.g. in VS Code).
   1. General status
   1. Provide quick links to relevant related data (e.g. PR, issue, etc.)
   1. Ability to click a link to get to the detailed session view
1. A CLI tool for spawning Copilot coding agent jobs and tracking them in the CLI (streaming back logs, allowing follow up comments)

## Approach

This new set of endpoints will be available at or under `/jobs` in the `sweagentd` service which currently translate to `https://api.githubcopilot.com/agents/swe/jobs` in prod. You should use the versioned variation of this endpoint whenever possible (e.g. revision `v0` is at `https://api.githubcopilot.com/agents/swe/jobs/v0`). Authentication and authorization will be handled by `sweagentd` with help from existing monolith twirp endpoints for validating access. More information will be described in the following sections.

### Endpoints

#### Auth

Each endpoint requires a GitHub App / OAuth App user token (or classic PAT for testing) with equivalent of the following scopes for the requested repository:

- `metadata:read`
- `contents:write`
- `pull_request:write`
- `actions:write`

For classic PATs and OAuth apps, the `repo` scope covers `metadata`, `contents`, `pull_request`, and `actions`.

While we recommend the token be repo scoped where possible, **Copilot coding agent will not inherit permissions** from this token so it will not be over privileged regardless. See [here](https://github.com/github/sweagentd/blob/main/docs/tokens-and-authz-in-actions.md) for info about token use within Actions for what the agent itself receives.

For authorization, please be aware that the user tied to the token must also have:
1. Push / contents write access to the repository regardless of the token's scope
1. Copilot coding agent enabled for both their user and the related repository in the request
1. Sufficient quota to perform the operation when creating a job

Within the four walls of GitHub, GitHub privileged Apps with the `coding_agent_job_execution` capability can opt to use a token with just `contents:write` / `push` instead. This is to accommodate internal scenarios where the user is signed in and already known to have these other privileges. However, we recommend using the full set of scopes wherever possible.

> **Note:** Fine grained PATs are not currently supported, and we recommend only using PATs during development.

For request headers:
1. The token should be passed in the `Authorization` header as a Bearer token, e.g. `Authorization: Bearer <token>`.
1. For security, please also include a User-Agent header in your requests, e.g. `User-Agent: <your-app-name>` so we can better track down where unexpected requests may be coming from.

On addition. when creating a job, please be sure to include an `event_type` related to your specific client in the request body for similar reasons.

In addition to standard `Bearer` tokens, calls from the monolith can opt to use encrypted `GitHub-Bearer` tokens instead since sweagentd's CAPI proxy endpoint will automatically decrypt them and pass the underlying tokens to `sweagentd` ([see here for details](https://github.com/github/copilot-api/blob/6414ab77de3b01bdadc1793898af43e427f7d05b/pkg/agent/agentproxy/agentproxy.go#L61-L93)).

#### Versioning

Versioning is achieved with URL path segments. 

| Version | URL |
|---------|-----|
| latest   | `https://api.githubcopilot.com/agents/swe/jobs` |
| `v0`   | `https://api.githubcopilot.com/agents/swe/v0/jobs` |
| `v1`   | `https://api.githubcopilot.com/agents/swe/v1/jobs` |

You should **always** use a versioned URL outside of development. Note that currently CAPI is intercepting the `X-GitHub-Api-Version` in the request, so we do not pay attention to this header today.

#### **POST** `/jobs/{owner}/{repo}` - Create Job (Task)

**Status:** Implemented. v1 update released 8/28/2025

This endpoint focuses on queuing up a task for Copilot coding agent to work on. It is tied to a repository, repository owner, and an end user that queued up the work. This encapsulates the logic for creating an assignment, branch and pull request, and queuing up job execution in one API call.

We recommend using the **`v1` version** of this endpoint. It returns faster since it does not wait until a PR or branch is created (each of which can be surprisingly slow in large repos). Clients can then use the `GET` endpoint to get the status of the job, whether an error occurred, and the related pull request / branch once created.

The `v0` version of this API includes PR details, but has a slower response time (>5s).

**Request Body**

Note that the repo owner and repo name are required, but come from the URL. Only problem statement is required in this body content.

```jsonc
{
  // [Required] The problem statement that the agent should work on.
  "problem_statement": "Create me a nice README", // required
  // [Optional] Any filtering should be applied to the problem statement: none, markdown, and hidden_characters
  "content_filter_mode": "hidden_characters", // Default
  // [Optional] Settings for the PR that will be created
  "pull_request": {
    "title": "Some PR title",
    "body_placeholder": "Text that should appear in the PR to start",
    "body_suffix": "A suffix that should appear at the bottom of all PR body updates",
    "base_ref": "refs/heads/some-branch", // If omitted, uses the default branch
    "head_ref": "refs/heads/copilot/some-branch", // If omitted, a new branch will be created. Branch must be prefixed with `copilot/`.
    "labels": ["some-label"] // An array of label strings
  },
  "run_name": "A name that should appear on the Actions run that is triggered",
  // [Optional] Triggering event properties
  "event_type": "", // An event type for the session that will be created, used to track the source of jobs in telemetry. Set this to a value that describes the source of your job, e.g. `agents_panel`, `jira`, `vs_code_remote_agent_tool_invoked`
  "event_url": "", // An event URL for the session that will be created
  "event_identifiers": [""] // A list of string identifiers for the session that will be created
}
```

**Response**

`201 Created`

Errors:

*For the `v1` endpoint, these error codes may also be found in the `error.response_status_code` field of the `GET` endpoint. Particularly `409 Conflict` and `422 Unprocessable Entity`.*

- `400 Bad Request` - Incorrect information was passed into the endpoint
- `401 Unauthorized` - User is not authorized to call this endpoint or does not have push rights to the repo
- `402 Payment Required` - User has no remaining quota for premium requests
- `403 Forbidden` - User is authorized to call this endpoint, but the user or repository does not have the Coding Agent enabled.
- `404 Not Found` - Repository or other resource not found. Also used when an app or user is on the "disallow" list to obfuscate.
- `409 Conflict` - A PR already exists for the specified base and head refs
- `422 Unprocessable Entity` - A branch protection rule or other rule is preventing branch setup or PR creation
- `500 Internal Server Error` - Something went wrong on the server side

**v1 Response Body**

```jsonc
{
  "job_id": "some-job-id",
  "session_id": "<ID for automatically created session>",
  "actor": {
    "id": "<user ID>",
    "login": "<user login>"
  },
  "created_at": "<timestamp>",
  "updated_at": "<timestamp>",
}
```

**v0 Response Body**

```jsonc
{
  "job_id": "some-job-id",
  "session_id": "<ID for automatically created session>",
  "status": "<job status>",
  "actor": {
    // gg.User associated with the token used to create the job
  },
  "created_at": "<timestamp>",
  "updated_at": "<timestamp>",
  "pull_request": {
    // gg.PullRequest for the job
  }
}
```


**Response**

Same as POST `/jobs/{owner}/{repo}`

#### **GET** `/jobs/{owner}/{repo}/{job_id}`, `/jobs/{owner}/{repo}/session/{session_id}` - Get Job Status

**Status:** Implemented

> **NOTE:** For user facing information, you should typically use the **[session API](https://github.com/github/copilot-api/blob/main/docs/api/session.md)** to get details about an executing job rather than this endpoint.

This endpoint retrieves the internal details of a job with a particular eye to getting visibility to its status and last update date. As a result, the initial version of this API returns only key information rather than the full details of the associated pull request or workflow run. We can add a version of this API that returns these details at a later point should the need arise, but we would likely want to hydrate it through the monolith.

**Response**

`200 OK`

Errors:

- `400 Bad Request` - Incorrect information was passed into the endpoint
- `401 Unauthorized` - User is not authorized to call this endpoint or does not have push rights to the repo
- `403 Forbidden` - User is authorized to call this endpoint, but the user or repository does not have the Coding Agent enabled.
- `404 Not Found` - Repository or job not found. Also used when an app or user is on the "disallow" list to obfuscate.
- `500 Internal Server Error` - Something went wrong on the server side

**Response Body**

```jsonc
{
  "job_id": "some-job-id",
  "session_id": "<ID for automatically created session>",
  "problem_statement": "<problem statement passed in when creating the job (not the PR text)>",
  "content_filter_mode": "<content filter mode if set>",
  "status": "<job status>",
  "result": "<job result>",
  "actor": {
    "id": "<User ID>",
    "login": "<User login>"
  },
  "created_at": "<timestamp>",
  "updated_at": "<timestamp>",
  "pull_request": {
    "id": "<PR ID>",
    "number": "<PR number>"
  },
  //If a workflow run has been started
  "workflow_run": {
    "id": "<Workflow Run ID>"
  },
  // If the job has errors
  "error": {
    "message": "<Error message>",
    "response_status_code": "<Optional status code that is representative of the class of error that was encountered>",
    "service": "<system or sub-component that caused the error. e.g. git>"
  },
  "event_type": "", // If specified
  "event_url": "", // If specified
  "event_identifiers": [""] // If specified
}
```

#### **POST** `/jobs/{owner}/{repo}/{job_id}/cancel`, `/jobs/{owner}/{repo}/session/{session_id}/cancel` - Cancel Job

**Status:** Implemented.

These endpoints allow a user to cancel a job that they have queued up. Either a Job ID or a Session ID can be used to cancel the job. If both are provided, the Job ID will be used.

**Auth Token Scopes**

Same as **POST** `/jobs/{owner}/{repo}`

**Response**

`204 No Content`

Errors:

- `400 Bad Request` - Incorrect information was passed into the endpoint
- `401 Unauthorized` - User is not authorized to call this endpoint or does not have push rights to the repo
- `403 Forbidden` - User is authorized to call this endpoint, but the user or repository does not have the Coding Agent enabled.
- `404 Not Found` - Repository or job not found. Also used when an app or user is on the "disallow" list to obfuscate.
- `409 Conflict` - Job has already been cancelled.
- `500 Internal Server Error` - Something went wrong on the server side

#### **PUT** `/jobs/{owner}/{repo}/{job_id}` - Update Job

**Status:** Not yet implemented.

> **NOTE:** This endpoint should **NOT** be implemented until we have a way to block the agent from calling it directly. The `/agent/job` endpoint requires a nonce that cannot be required here. So we either need a specific scope, or to block tokens generated Copilot coding agent from calling this endpoint - at least unless the token is encrypted, has a nonce, or a shared secret that can verify it is from an expected client.

This endpoint updates the job with information related to its current state and progress.

**Request Body**

```jsonc
// TODO
```

**Response**

`202 Accepted`

Same as **GET** `/jobs/{owner}/{repo}/{job_id}`

#### **GET** `/jobs/{owner}/{repo}/pulls/{prNumber}` - List Jobs for Pull Request

**Status:** Implemented

This endpoint retrieves all jobs associated with a specific pull request number. This is useful for displaying job history and status in PR-related UI contexts.

**Auth Token Scopes**

Same as **POST** `/jobs/{owner}/{repo}`

**Response**

`200 OK`

Errors:

- `400 Bad Request` - Incorrect information was passed into the endpoint (e.g., invalid PR number)
- `401 Unauthorized` - User is not authorized to call this endpoint or does not have push rights to the repo
- `403 Forbidden` - User is authorized to call this endpoint, but the user or repository does not have the Coding Agent enabled.
- `404 Not Found` - Repository not found. Also used when an app or user is on the "disallow" list to obfuscate.
- `500 Internal Server Error` - Something went wrong on the server side

**Response Body**

Returns an array of job objects. If no jobs are found for the specified pull request, an empty array is returned.

```jsonc
[
  {
    "job_id": "some-job-id",
    "session_id": "<ID for automatically created session>",
    "problem_statement": "<problem statement passed in when creating the job>",
    "content_filter_mode": "<content filter mode if set>",
    "status": "<job status>",
    "actor": {
      "id": "<User ID>",
      "login": "<User login>"
    },
    "created_at": "<timestamp>",
    "updated_at": "<timestamp>",
    "pull_request": {
      "id": "<PR ID>",
      "number": "<PR number>"
    },
    "workflow_run": {
      "id": "<Workflow Run ID>"
    },
    "error": {
      "message": "<Error message>",
      "response_status_code": "<Optional status code>",
      "service": "<system or sub-component that caused the error>"
    },
    "event_type": "",
    "event_url": "",
    "event_identifiers": [""]
  }
  // ... additional jobs
]
```
