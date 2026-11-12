# GitHub Copilot Coding Agent - Development Setup

> [!TIP]
> **🐳 You are viewing the Docker runner setup guide.**
> 
> There are two ways to develop sweagentd:
> | Setup | Best for | Guide |
> |-------|----------|-------|
> | **Docker runner** (this doc) | Quick iteration, lightweight development | You're here! |
> | **GitHub Actions runner** | Full E2E testing with Actions infrastructure | [Service dev setup with GitHub](./service-dev-setup-with-github.md) |

## Prerequisites

- 1Password access (optional but highly recommended) - see [these instructions](https://github.com/github/copilot-api/blob/main/docs/dev/dotcom-codespaces-development.md#set-secrets)
    - This is a hard requirement if you plan on running CAPI locally

## Quick Start

### 1. Create Codespace

```bash
# Create alias
gh alias set --shell sweagentd-docker 'gh cs code -c "$(gh cs create -R 'github/github' --devcontainer-path '.devcontainer/coding-agent/devcontainer.json' -b 'master' -m 'xLargePremiumLinux256gb')"'

# Launch codespace (takes ~5 minutes first time)
gh sweagentd-docker
```

### 2. Setup Environment

```bash
# Inside codespace terminal
cd /workspaces/github && script/setup-codespaces-copilot-swe-agent-v2
```

### 2. Verify Environment

```bash
# Check GitHub server is running
curl http://github.localhost

# If not running, start it:
script/dx/server-start
```

### 3. Start Sweagentd Development

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

### Option B: Issue Assignment

1. Create issue at `http://github.localhost/github/private-server/issues`
2. Assign to `Copilot`
3. Watch for 👀 reaction and PR creation

## Optional Configuration

### Sync Runtime Changes
```bash
cd /workspaces/sweagentd/runtime && npm run docker:build
```

### Enable CAPI or UI Features

For a full end-to-end experience, you'll need to have CAPI running locally. You can enable it by following the command below:

1. Ensure dotcom server is stopped: `script/dx/server-stop`
2. Run setup with CAPI flag: `cd /workspaces/github && script/setup-codespaces-copilot-swe-agent-v2 --capi`
3. Verify CAPI is running: `overmind echo | rg copilot-api`

With CAPI running, you can now use the Agent Panel as well as Mission Control 🎉

## Testing the Job API

The Job API allows you to create, monitor, and cancel coding agent jobs. Test it before deploying changes. To get familiarized run `script/job-api --help`.

## Important Notes

⚠️ **Only use private repositories in the `github` organization** - others won't work

📁 **Job logs:** All jobs log to `runtime-logs/<job-id>.log`

🔄 **Restart sweagentd** if you restart the GitHub server to maintain event flow

## Common Tasks

### Enable Debug Logging
Set Actions variable `COPILOT_AGENT_DEBUG` to `true` and rebuild the Docker runner.

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
