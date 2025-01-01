# ghes-resource-migrator

The GitHub Enterprise Server resource migrator. Also referred to as *scotty*.

## Deploying on Enterprise Server

As this application is intended to be ran on Enterprise Server, it can be useful to deploy and manually test code
there from time to time.

To do this, follow the following procedure:

1. In #ghes-infrastructure-operations, run `.gheboot VERSION`. Version is the version to be launched (at the time of
   writing the latest version is 3.14).
2. Wait for your instance of Enterprise Server to boot. This can take up to 30 minutes.
3. On your local machine, cross-compile the binary by running `GOOS=linux GOARCH=amd64 go build`.
4. Copy the binary to the Enterprise Server instance: `scp -P122 ghes-resource-migrator admin@[HOSTNAME]:/home/admin/`
5. SSH to Enterprise Server: `ssh -p122 admin@[HOSTNAME]`
6. Get the private instance IP: `ip address show dev eth0`
7. Create a UFW rule to allow traffic to the webhook receiver: `sudo ufw allow from [PRIVATE IP] proto tcp port 9178`
8. Remove rule that stops hookshot from communicating over localhost: `sudo iptables -D ufw-before-output -o lo -m owner --uid-owner hookshot -j REJECT`
9. Fire up a screen, `screen -S migrator`.
10. Run the migrator: `./ghes-resource-migrator 2>&1 | tee -a migrator.log`
11. Through the Enterprise Server Web UI, create a new repository.
12. Configure a new webhook, with a destination of `http://[PRIVATE IP]:9178/api/v1/webhooks`
13. Back in your SSH session, you should see the `ping` event come through.

In the future, the firewall will not need to be modified. Follow [this issue](https://github.com/github/migrations-vnext/issues/138)
to track progress.

## Running the migrate-repository command
> [!NOTE]
> These instructions assume you are running a gheboot instance and a
> `github/github` codespace with the `github/migrations-vnext` repository cloned
> into the `/workspaces` directory.

This command will fetch resources from the source GitHub API and send them
to the target GitHub API. We are using the monolith to proxy requests before
sending them to mvnd and the rest of the ingestion pipeline. Because of this,
there is some additional setup required to make this work.

1. On the gheboot instance UI, create a repository and any additional resources
   to migrate.
1. On the gheboot instance UI, create a PAT with `repo` permissions.
1. In your [codespace UI](http://avocado-gmbh.ghe.localhost/settings/tokens),
   create a PAT with `admin:enterprise` permissions, which will be used to
   authenticate requests from the crawler to the GitHub API.
1. Start gh/gh in Proxima mode with necessary feature flags and environment
   variables:
   ```shell
   cd /workspaces/github
   script/mvnd-enabled-server
   ```
1. In other terminals, start docker and the mvn services:
   ```shell
   cd /workspaces/migrations-vnext
   ```
   ```shell
   script/docker
   ```
   ```shell
   script/mvnd
   ```
   ```shell
   script/mvnworker
   ```
   ```shell
   script/mvndagworker
   ```
1. Run the `migrate-repository` command with the needed flags:
   ```shell
   go run ./cmd/ghes-resource-migrator migrate-repository \
      --ghes-url your-gheboot-url \
      --ghes-token your-pat-from-the-gheboot-instance \
      --ghes-username ghe-admin \
      --ghes-password password-for-ghe-admin \
      --migration-target-url http://api.avocado-gmbh.ghe.localhost \
      --migration-target-pat your-pat-from-the-codespace \
      --repository the-name-of-the-repo-you-created
   ```

### Enabling Git Sync

To also sync Git data during migration, you'll need to:

1. Make your gh/gh server (running on port 80) publicly accessible. The easiest way is to use the GitHub Codespaces port forwarding feature:
   - Open the Ports tab in VS Code
   - Find port 80 in the list
   - Change its visibility from "Private" to "Public"
   - Copy the public URL (e.g. `https://user-workspace-abc123.preview.app.github.dev`)

1. Get the source repository's git path from stafftools:
   - Go to `/stafftools/repositories/{owner}/{repo}/disk` on your gheboot instance
   - Copy the repository path shown there

1. Add these additional flags to the migrate-repository command:
   ```shell
   --migration-target-git-url https://user-workspace-abc123.preview.app.github.dev \
   --git-repo-path /path/to/source/repo/from/stafftools \
   --git-sync-interval 3s
