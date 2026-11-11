# GitHub Copilot Coding Agent - Development Setup

> [!TIP]
> **🐳 You are viewing the Docker runner setup guide (recommended).**
> 
> The Actions runner setup is **deprecated**. Use this Docker-based guide for all local development.
> The legacy Actions runner guide is kept for [historical reference](./service-dev-setup-with-github.md) only.

## Prerequisites

- 1Password access (optional but highly recommended) - see [these instructions](https://github.com/github/copilot-api/blob/main/docs/dev/local-development.md)
    - This is a hard requirement if you plan on running CAPI locally

## Quick Start

### 1. Create Codespace

**Option 1:** 
```bash
# Create alias
gh alias set --shell sweagentd-docker 'gh cs code -c "$(gh cs create -R 'github/github' --devcontainer-path '.devcontainer/coding-agent/devcontainer.json' -b 'master' -m 'xLargePremiumLinux256gb')"'

# Launch codespace (takes ~5 minutes first time)
gh sweagentd-docker
```

**Option 2:** 
1. Go to https://github.com/github/github
2. Select code --> codespaces --> new with options
    <img width="775" height="383" alt="Screenshot 2026-04-29 at 2 54 58 PM" src="https://github.com/user-attachments/assets/e13f9348-29fc-45fc-9b51-c9ca83c8be8f" />'

3. Select the coding agent development dev container configuration
    <img width="906" height="640" alt="Screenshot 2026-04-29 at 2 55 46 PM" src="https://github.com/user-attachments/assets/5c70f147-e219-4298-a3b1-42d368529442" />

4. Click create codespace

### 2. Setup Environment

For full end-to-end development with sweagentd, Mission Control, CAPI, and GitHub, see the [Mission Control full end-to-end stack development docs](https://github.com/github/copilot-mission-control/blob/main/docs/dev/e2e-development.md).

Tip: As outlined in the docs above, run `/cmc-medic` in the CLI to troubleshoot any issues you have. You can instruct copilot to set up and start the services for you.

#### Alternative Setup - Sweagentd Only 

##### 1. Run Set-up script
```bash
# Inside codespace terminal
cd /workspaces/github && script/setup-codespaces-copilot-swe-agent-v2
```

##### 2. Verify Environment

```bash
# Check GitHub server is running
curl http://github.localhost

# If not running, start it:
script/dx/server-start
```

##### 3. Start Sweagentd Development

```bash
# Navigate and start server
cd /workspaces/sweagentd && script/server
```

**Note:** Sign in at `http://github.localhost` as `monalisa` (no password required)

## Verify Your Setup

Choose either method to confirm everything works:

### Option A: Job API (Recommended)

```bash
script/job-api new github/private-server '{"problem_statement":"Create a nice README."}'
```

**Expected result:** New job created, PR opened against `github/private-server`

**View logs:** `tail -f runtime-logs/<job-id>.log`

### Option B: Kick off a run in the Agents tab in a repo (Prereq: Full end-to-end setup)

1. Go to http://github.localhost/monalisa/smile/agents?author=monalisa
2. Kick off a new agent task 

### Option C: Issue Assignment

1. Create issue at `http://github.localhost/github/private-server/issues`
2. Assign to `Copilot`
3. Watch for 👀 reaction and PR creation

## Optional Configuration

### Sync Runtime Changes

Local runtime changes are picked up automatically: `.env.example` ships
`DOCKER_DEV_MOUNT_RUNTIME=/workspaces/sweagentd/runtime`, so when you copy
it to `.env` the agent container bind-mounts your local `dist*` folders.
Just build the bundle you're working on:

```bash
# Build the runtime bundle(s) you're working on; pick whichever apply:
cd /workspaces/sweagentd/runtime
npm run build:cca-v1       # main agent (`dist/`)
npm run build:cca          # CCA agent (`dist-cca/`)
npm run build:cca-v3       # CCA-v3 agent (`dist-cca-v3/`)
npm run build:claude       # Claude agent (`dist-claude/`)
npm run build:codex        # Codex agent (`dist-codex/`)
npm run build:mcp-client   # MCP tools server (`dist-mcp-client/`)
```

> **Note:** If you just added `DOCKER_DEV_MOUNT_RUNTIME` to your `.env`, restart sweagentd once so the server process picks up the new variable: `cd /workspaces/sweagentd && script/server`

Bind mounts are live, so subsequent rebuilds take effect on the next job
without restarting sweagentd or rebuilding the Docker image. Each folder is
mounted only if it exists locally; missing folders fall back to the Docker
image's bundled version, so on a fresh checkout this default is a no-op.

If your `.env` predates this default, add the line manually or copy the
block from `.env.example`. To opt out (e.g., to test exactly what's baked
into the Docker image), comment out `DOCKER_DEV_MOUNT_RUNTIME` or set it to
an empty string.

#### Alternative: Rebuild the Docker Image

For changes that require a full image rebuild (e.g., updates to the runtime
Dockerfile or system dependencies):

```bash
cd /workspaces/sweagentd/runtime && npm run docker:build
```

### Enable CAPI or UI Features

For a full end-to-end experience, you'll need to have CAPI running locally. You can enable it by following the command below:

1. Ensure dotcom server is stopped: `script/dx/server-stop`
2. Run setup with CAPI flag: `cd /workspaces/github && script/setup-codespaces-copilot-swe-agent-v2 --capi`
3. Verify CAPI is running: `overmind echo | rg copilot-api`

With CAPI running, you can now use the Agent Panel as well as Mission Control 🎉

### Enable the GitHub MCP Server
See [MCP E2E Agent Setup](e2e-mcp-agent-setup.md) for instructions on enabling the GitHub MCP Server or the test echo server.

## Testing the Job API

The Job API allows you to create, monitor, and cancel coding agent jobs. Test it before deploying changes. To get familiarized run `script/job-api --help`.

## Important Notes

⚠️ **Only use private repositories in the `github` organization** - others won't work

📁 **Job logs:** All jobs log to `runtime-logs/<job-id>.log`

🔄 **Restart sweagentd** if you restart the GitHub server to maintain event flow

## Common Tasks

### Enable Debug Logging
Set Actions variable `COPILOT_AGENT_DEBUG` to `true` and rebuild the Docker runner.

### Enable Runtime-Tools MCP Debug Logging

Runtime-tools MCP server logs are automatically enabled for the Docker launcher. After a job runs:

```bash
cat /tmp/cca-mcp-debug-logs/runtime-tools.log
```

### Restarting CAPI

```bash
cd /workspaces/copilot-api && script/manage-overmind-capi restart
```

## Troubleshooting

### Port Forwarding Issues
**Fix:** Reload Window (F1 → "Reload Window" or Ctrl/Cmd+Shift+W)

### Disk Full Warnings
**Fix:** `rm /workspaces/github/log/*`

### "Could Not Update Assignee" Error
```bash
# Stop dotcom server, then run:
bin/rake db:migrate db:test:prepare
bin/setup-codespaces-copilot-swe-agent
# Restart dotcom server
```

### Shell Compatibility (zsh users)
Use `bash` for commands in `/workspaces/github` or copy aliases from `~/.bashrc` to `~/.zshrc`

### View Codespace Setup Logs
F1 → "Codespaces: View Creation Logs"

### Aqueduct Protobuf Updates
```bash
go generate ./internal/aqueduct/jobs/...
# Commit generated files
```

## Recovery Required (Create New Codespace)

In most scenarios, it's easier to create a new codespace than to recover from issues with the existing one.

## ⛔ Do Not
- ❌ Run `bin/setup --force` (wipes all data)
- ❌ Run `docker system prune` (deletes critical images)
- ❌ Rebuild codespace (creates unrecoverable state - create new instead)

## Additional Resources
- [Job API ADR](./adr/0001-create-job-api.md)
