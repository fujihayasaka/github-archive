## The Cargo package manager adapter

### Running the adapter

Run the adapter with `package_manager_adapters/script/start cargo`

### Running the tests

Run adapter tests with `package_manager_adapters/script/test cargo`

### Running a production backfill
1. Ensure production Moda deploy has latest DG-API code!
1. Chatops to lock "scripts" env: `.deploy lock dependency-graph-api/master to scripts`
1. SSH to bastion ops-shell (pick a site like "ac4-iad")
1. Obtain a shell session on a "scripts" pod (preferably in same site as the ops-shell!)
  - Example:
    - Find a pod: `kubectl --context general-2-ac4-iad get all -n dependency-graph-api-scripts`
    - Shell session: `kubectl --context general-2-ac4-iad exec -i -t -n dependency-graph-api-scripts scripts-99599b679-mhcpj -- /bin/bash`
1. From the "scripts" pod shell session (assumes running as `root`):
  - `apt install tmux`
  - `tmux -S /tmp/your-backfill-name.sock new -s backfill_session_name`
  - `tmux -S /tmp/your-backfill-name.sock attach`
1. From your `tmux` session in your "scripts" pod shell session:
  - `cd package_manager_adapters/cargo; ./wrapper import`
  - To restart from partial-fail, see instructions [here](https://github.com/github/dependency-graph-api/blob/master/package_manager_adapters/cargo/lib/cargo_snapshot.rb#L37-L60)
1. Detatch from tmux session with `ctrl-b` then `d` to avoid losing in-flight backfill!
1. Keep an eye on dashboards and graphs:
  - https://app.datadoghq.com/dashboard/ekt-485-634/dependency-graph-jobs
  - https://app.datadoghq.com/dashboard/9im-uhe-hwd/dg-package-manager-adapters
  - https://sentry.io/organizations/github/issues/?project=1858608&statsPeriod=1h
1. Periodically check in with your running tmux session:
  - From ops shell box: `tmux -S /tmp/your-backfill-name.sock a`
  - Remember to detatch between checks!
1. Be kind, rewind! When the backfill is complete:
  - Close out your tmux session on ops-shell
  - Unlock the "scripts" deploy
  - Redeploy "scripts" env to sync missed deploys
