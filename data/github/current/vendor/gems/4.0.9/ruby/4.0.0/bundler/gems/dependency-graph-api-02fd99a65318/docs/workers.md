This document describes all of the background workers that power Dependency Graph.

The authoritative specification of our jobs is the set of `.yaml` files in the
[config/kubernetes/workers/](../config/kubernetes/workers/) tree.
Each time a PR that changes this tree is deployed to production,
the [Heaven](https://github.com/github/heaven) service relaunches the jobs.

## Daemon workers

These are workers that are constantly running and polling some service for changes to react to.
Their Kubernetes job kind is `Deployment` and they live in the `deployments/` subdirectory.

| Worker name | source | Description |  Service Requirements |
|:--|:--|:--|:--|
| ingest_packages | [source](../config/kubernetes/workers/deployments/ingest_packages.yaml)  | Listens on the `dependency_graph.etl.package_versions` topic and [loads a package version's definition](https://github.com/github/dependency-graph-api/blob/d45cb7b84e9540fa5e5039342d442b3af1346754/etl/ingest/package_stage.rb#L59) into the database | Kafka, Mysql DB|
| repo_manifest_file_changes | [source](../config/kubernetes/workers/deployments/repo_manifest_file_changes.yaml) | Listens on [RepositoryManifestFileChange](https://tributary.githubapp.com/schemas/github-dependencygraph-v0-RepositoryManifestFileChange) topic and converts raw content into generic manifest |  Hydro, Kafka |
| repo_manifest_file_deleted | [source](../config/kubernetes/workers/deployments/repo_manifest_file_deleted.yaml) | Listens on [RepositoryManifestFileDeleted](https://tributary.githubapp.com/schemas/github-dependencygraph-v0-RepositoryManifestFileDeleted) topic and removes all dependencies for a deleted manifest file in a repository |  Hydro, Kafka, Mysql DB |
| repo_visibility_changes | [source](../config/kubernetes/workers/deployments/repo_visibility_changes.yaml) | Listens on [RepositoryVisibilityChanged](https://tributary.githubapp.com/schemas/github-v1-RepositoryVisibilityChanged) topic and flips the repository visibility for a copy of the repository in Dependency Graph databases |  Hydro, Mysql DB|
| repositories_delete | [source](../config/kubernetes/workers/deployments/repository_deleted.yaml) | Listens on [RepositoryDeleted](https://tributary.githubapp.com/schemas/github-v1-RepositoryDeleted) topic and deletes all packages, manifests & dependencies from the mysql database if a repository gets deleted  | Hydro, Mysql DB|


## Periodic workers

These workers are run on a specified timed interval.
Their Kubernetes job kind is `CronJob` and they live in the `cronjob/` subdirectory.

| Worker name | source | Description | Frequency| Service Requirements |
|:--|:--|:--|:--|:--|
| abstract_dependent_counts | [source](../config/kubernetes/workers/cronjobs/abstract_dependent_counts.yaml) | Updates the `dg_abstract_repository_dependency_counts` & `dg_abstract_package_dependency_counts` with accurate counts of their dependencies | Every 15 minutes | Mysql DB |
| extract_ruby_packages | [source](../config/kubernetes/workers/cronjobs/extract_ruby_packages.yaml) | Pulls data from `rubygems.org` and publishes the package manifests to SinkProxy | Every day at midnight (PST) | SinkProxy |
| extract_maven_packages | [source](../config/kubernetes/workers/cronjobs/extract_maven_packages.yaml) | Pulls data from `Maven central` and publishes the package manifests to SinkProxy | Every day at 2AM (PST) | SinkProxy |
| extract_nuget_packages | [source](../config/kubernetes/workers/cronjobs/extract_nuget_packages.yaml) | Pulls data from `nuget.org` and publishes the package manifests to SinkProxy | Every day at 4AM (PST) | SinkProxy |
| extract_go_packages | [source](../config/kubernetes/workers/cronjobs/extract_go_packages.yaml) | Pulls data from `index.golang.org` and publishes the package manifests to Fjord | Every minute | Redis, for locking to ensure concurrency |
| extract_pypi_packages | [source](../config/kubernetes/workers/cronjobs/extract_pypi_packages.yaml) | Pulls data from `pypi.python.org` and publishes the package manifests to SinkProxy | Every 30 minutes | SinkProxy |
| extract_composer_packages | [source](../config/kubernetes/workers/cronjobs/extract_composer_packages.yaml) | Pulls data from `repo.packagist.org` and publishes the package manifests to SinkProxy | Every 10 minutes | SinkProxy |
| sync_vulnerabilities | [source](../config/kubernetes/workers/cronjobs/sync_vulnerabilities.yaml) | Extracts vulnerable version ranges from `VulnerableVersionRange` model in dotcom creates rows in `dg_vulnerable_version_ranges` table to alert repositories on vulnerable packages | Every 15 minutes | Mysql DB |

Note: Actions does not have a worker for it's package manager adapter. When a manifest is ingested, the [ActionsPackageJob](../app/jobs/actions_package_job.rb) is run for all package releases.


## Kubernetes Incantations!
Brimley's orientation chatop: `.rem kuberneetus`
Here are some general incantations for managing _deployed pods_ of our services at the CLI using `kubectl` and friends from a bastion/ops shell box, and a brief playbook for using them to diagnose trouble.

### Getting Started
1. `ssh` into an ops-shell box. I have an `.ssh/config` recipe for this but the critical bit is to apply _agent forwarding_ from your laptop. See the Hub for details
1. Log into Vault for access to k8s deploy regions/sites: `. vault-login` (be prepared to supply your GH password and paste some FIDO URLs into your browser!)

My `.ssh/config` alias for this (I've seen a lot of variants, adjust to taste!):
```
Host bastion*.githubapp.com vault-bastion*.githubapp.com
  ForwardAgent yes
  User <YOUR_GITHUB_LOGIN>
  IdentityFile ~/.ssh/id_rsa
  ControlMaster auto
  ControlPath /tmp/%r@%h:%p
  ControlPersist 600

Host ops-shell-ac4
  HostName shell.service.ac4-iad.github.net
  ForwardAgent yes
  User <YOUR_GITHUB_LOGIN>
  IdentityFile ~/.ssh/id_rsa
  ControlPath /tmp/%r@%h:%p
  ProxyJump bastion.githubapp.com
```

### General Usage

#### Locate and view status of deployed pods
* Run `gh-k8s-clusters --profile general --status ready` to see a list of possible deploy sites you can run `kubectl` commands against
* Each Dependency Graph deployment is namespaced like this: `<service_name>-<deployment>`. Example: `dependency-graph-api-production`
* You can use `xargs` or Bash loops to iterate through deploy sites and/or namespaces to "cast a wider net" in your `kubectl` commands
* Examples:
    * `kubectl --context general-2-ac4-iad get pods -n dependency-graph-api-production` to view all `workers` pods in `general-2-ac4-iad` deploy site
    * `gh-k8s-clusters --profile general | xargs -I % bash -c 'echo % ; kubectl --context % get pods -n dependency-graph-api-production'` to view all `workers` pods across all `general` deploy sites
    * `gh-k8s-clusters --profile general | xargs -I % bash -c 'echo % ; kubectl --context % get pods -n dependency-graph-api-production | grep extract-pypi-packages'` to view all `extract-pypi-packages` pods from the `workers` deployment on all deploy sites

Note that typical output includes job _status, uptime, etc._ that are useful for triaging problems. See `kubectl` docs for more formatting options!

#### View or tail logs from a target pod
Once you've located a pod of interest, you can view or tail the logs using the site, namespace, and pod name. Examples:
* `kubectl --context general-3-va3-iad logs -n dependency-graph-api-production extract-cargo-packages-27891135-px7tw` to view the most recent run log for this cronjob
* ` kubectl --context general-3-va3-iad logs -f -n dependency-graph-api-production aqueduct-resqued-worker-6c546b845f-4mlxs` to _tail_ the logs from a long-running `worker` pod (not a `CronJob`)

#### Obtain a shell session on a target pod
Once you've located a pod of interest, you can `ssh` into it directly: `kubectl --context <SITE> -n <DG_SERVICE>-<DEPLOYMENT> exec -it <POD NAME> -- /bin/bash`. _NOTE: you cannot `ssh` into `CronJob` type pods unless they are actively running._ Example:
* `kubectl --context general-3-va3-iad -n dependency-graph-api-scripts exec -it scripts-5c7bbbf564-g8hkd -- /bin/bash` to obtain a shell into a `scripts`-role pod in the `general-3-va3-iad` site

#### Delete a target pod, deployment etc.
**CAUTION!!!** This operation is destructive, the equivalent of pressing the red `DELETE` buttons in the [Moda homepage](https://moda.githubapp.com/apps/dependency-graph-api). Once deleted, you can only "revive" a pod/deployment/site using an appropriate `.deploy` chatop in Slack!

As detailed in the playbook scenario below, this command should be reserved for times when a cronjob or scripts (non-critical path) pod or deployment has somehow gotten into a bad state and must be removed to unblock a fail state. Even in this case, a re-deploy of the role/deployment is a good idea immediately after using this command! Examples:
* `kubectl --context general-3-va3-iad delete pod -n dependency-graph-api-scripts scripts-5c7bbbf564-g8hkd` to delete a single `scripts` target pod deployed in `general-3-va3-iad` site under the `dependency-graph-api-scripts` namespace
* `kubectl --context general-3-va3-iad exec -i -t -n dependency-graph-api-scripts` **DANGER!** deletes _all_ `scripts` pods deployed to `general-3-va3-iad`, similar to Moda homepage buttons


### Playbook Example
A quick triage and bugfix scenario using the `kubectl` CLI:

* The DataDog PMA alarms indicate the `extract-pypi-packages` cronjob has started failing
* Looking through the Moda homepage pod logs for all such jobs across all deploy sites takes forever and can be lossy
* Splunk triage for this is messy b/c the current PMA job logs include multi-line bash and are very noisy
* Every cron job run is deployed to multiple sites, so a DB-based [locking script](https://github.com/github/dependency-graph-api/blob/master/package_manager_adapters/script/start_kube#L37-L56) wrapper is used to ensure only one of each type of identical cronjob can run at a time.

Steps to resolve:
We decide to rerun the job and see if the local logging surfaced the problem more easily:
```
# Vault login
ops-shell> . vault-login

# View status (and names!) of all `scripts` pods deployed to `general-3-va3-iad`
ops-shell> kubectl --context general-3-va3-iad -n dependency-graph-api-scripts get pods

# Example output:
NAME                            READY   STATUS      RESTARTS   AGE
scripts-5c7bbbf564-g8hkd        1/1     Running     0          37h
transition-template-job-6lzls   0/1     Completed   0          2d4h

# Select a pod, `ssh` into it, and attempt to run the broken PMA:
ops-shell> kubectl --context general-3-va3-iad -n dependency-graph-api-scripts  exec -it scripts-5c7bbbf564-g8hkd -- /bin/bash
scripts-5c7bbbf564-g8hkd> cd package_manager_adapters
scripts-5c7bbbf564-g8hkd> script/start_kube pypi

Example output:
11/01/2023, 12:00:12++ dirname script/start_kube
11/01/2023, 12:00:12+ scriptdir=script
11/01/2023, 12:00:12+ package_manager=pypi
11/01/2023, 12:00:12+ shift
11/01/2023, 12:00:12+ case "$package_manager" in
11/01/2023, 12:00:12+ echo 'Starting sink proxy...'
11/01/2023, 12:00:12Starting sink proxy...
11/01/2023, 12:00:12+ cd script/../..
11/01/2023, 12:00:12+ RAILS_LOG_TO_STDOUT=true
11/01/2023, 12:00:12+ script/etl/sink_proxy start
11/01/2023, 12:00:21I, [2023-01-11T20:00:21.235213 #9] INFO -- : Instrumentation: OpenTelemetry::Instrumentation::Rack was successfully installed with the following options {:allowed_request_headers=>[], :allowed_response_headers=>[], :application=>nil, :record_frontend_span=>false, :retain_middleware_names=>false, :untraced_endpoints=>["/status", "/_ping", "/_chatops"], :url_quantization=>nil, :untraced_requests=>nil}
11/01/2023, 12:00:21I, [2023-01-11T20:00:21.248301 #9] INFO -- : Instrumentation: OpenTelemetry::Instrumentation::ActionPack was successfully installed with the following options {:enable_recognize_route=>false}
11/01/2023, 12:00:21I, [2023-01-11T20:00:21.249787 #9] INFO -- : Instrumentation: OpenTelemetry::Instrumentation::ActiveSupport was successfully installed with the following options {}
11/01/2023, 12:00:21I, [2023-01-11T20:00:21.251089 #9] INFO -- : Instrumentation: OpenTelemetry::Instrumentation::ActionView was successfully installed with the following options {:disallowed_notification_payload_keys=>[], :notification_payload_transform=>nil}
11/01/2023, 12:00:21I, [2023-01-11T20:00:21.258078 #9] INFO -- : Instrumentation: OpenTelemetry::Instrumentation::ActiveRecord was successfully installed with the following options {}
11/01/2023, 12:00:21I, [2023-01-11T20:00:21.258203 #9] INFO -- : Instrumentation: OpenTelemetry::Instrumentation::Rails was successfully installed with the following options {}
11/01/2023, 12:00:21I, [2023-01-11T20:00:21.307467 #9] INFO -- : Instrumentation: OpenTelemetry::Instrumentation::Faraday was successfully installed with the following options {:peer_service=>nil}
11/01/2023, 12:00:26script/etl/sink_proxy_1: process with pid 55 started.
11/01/2023, 12:00:26+ sink_proxy_url=http://localhost:7777
11/01/2023, 12:00:26++ curl -s -o /dev/null -w '%{http_code}' http://localhost:7777/status
11/01/2023, 12:00:27+ [[ 000 != \2\0\0 ]]
11/01/2023, 12:00:27+ sleep 1
11/01/2023, 12:00:28++ curl -s -o /dev/null -w '%{http_code}' http://localhost:7777/status
11/01/2023, 12:00:28+ [[ 200 != \2\0\0 ]]
11/01/2023, 12:00:28+ echo 'Sink proxy up.'
11/01/2023, 12:00:28Sink proxy up.
11/01/2023, 12:00:28+ set +e
11/01/2023, 12:00:28+ case "$package_manager" in
11/01/2023, 12:00:28+ run_wrapper_with_lock -wait=false
11/01/2023, 12:00:28+ script/../../mysql-lock -lock=pma-pypi -dir=script/../pypi -user=dependency_graph_rw -password=2b01d892c25bddbb9fc9f0d9cd205357 -host=db-mysql-dependency-graph-rw.service.github.net -port=3306 -wait=false dependency_graph dg_locks ./wrapper run
11/01/2023, 12:00:28mysql-lock: lock "pma-pypi" held by "extract-pypi-packages-27891120-xnpj4:67@1673467220818316-3e1cf073"
11/01/2023, 12:00:28+ status=11
11/01/2023, 12:00:28+ '[' 11 = 11 ']'
11/01/2023, 12:00:28+ echo 'Failed to acquire leadership lock for job '\''pypi'\''. Nothing to do.'
11/01/2023, 12:00:28Failed to acquire leadership lock for job 'pypi'. Nothing to do.
11/01/2023, 12:00:28+ exit 0
```

AHA! The lock is held by a particular `extract-pypi-packages` pod even though no runs have successfully produced packages in hours! let's check on it:

```
# View status of all `worker` pods running `extract-pypi-packages` jobs, including status of latest run if inactive, across all deploy sites
ops-shell> gh-k8s-clusters --profile general | xargs -I % bash -c 'echo % ; kubectl --context % get pods -n dependency-graph-api-production | grep extract-pypi-packages'`

# Example output:

general-1-ash1-iad
extract-pypi-packages-27891060-5d58t                           0/1     Completed   0               115m
extract-pypi-packages-27891120-b2xww                           0/1     Completed   0               55m
general-1-azure-eastus
No resources found in dependency-graph-api-production namespace.
general-2-ac4-iad
extract-pypi-packages-27891060-7ntz4                           0/1     Completed   0                115m
extract-pypi-packages-27891120-smnn5                           0/1     Completed   0                55m
general-2-ash1-iad
extract-pypi-packages-27891060-b27qw                           0/1     Completed   0                 115m
extract-pypi-packages-27891120-xnpj4                           1/1     Running     0                 27h
general-2-azure-eastus
No resources found in dependency-graph-api-production namespace.
general-2-va3-iad
extract-pypi-packages-27891060-bbzkr                           0/1     Completed   0                 115m
extract-pypi-packages-27891120-p8xn2                           0/1     Completed   0                 55m
general-3-ac4-iad
extract-pypi-packages-27891060-vw7xj                           0/1     Completed   0                 115m
extract-pypi-packages-27891120-k8lnt                           0/1     Completed   0                 55m
general-3-azure-eastus
No resources found in dependency-graph-api-production namespace.
general-3-va3-iad
extract-pypi-packages-27891060-vqmq9                           0/1     Completed   0               115m
extract-pypi-packages-27891120-djdct                           0/1     Completed   0               55m
general-4-azure-eastus
No resources found in dependency-graph-api-production namespace.

# Notice - the pod holding the lock has been running for 27 hours without progress!

# Attempt to view logs
 ops-shell> kubectl --context general-2-ash1-iad -n dependency-graph-api-production logs -f extract-pypi-packages-27891120-xnpj4

# Example output:
...redacted...
10/01/2023, 07:00:54now="2023-01-10 15:00:54,726" package_manager=pypi log_message="Importing ImportSpec(package_name='sentry-dynamic-sampling-lib', version='1.0.1a2')"
10/01/2023, 07:00:55now="2023-01-10 15:00:55,117" package_manager=pypi log_message="Importing ImportSpec(package_name='ConnectionHandler', version='0.0.18')"
10/01/2023, 07:00:55now="2023-01-10 15:00:55,316" package_manager=pypi log_message="Importing ImportSpec(package_name='inels-mqtt-new', version='0.0.74')"
11/01/2023, 02:22:07[mysql] 2023/01/11 10:22:07 packets.go:123: closing bad idle connection: EOF
11/01/2023, 02:22:22[mysql] 2023/01/11 10:22:22 packets.go:123: closing bad idle connection: EOF

# That's odd! looks like an attempt to store the new checkpoint at the end
# of this run failed, and the process has been stuck for hours holding the lock

# Delete the pod so the wrapper script can release the lock and allow future cron runs to proceed
ops-shell> kubectl --context general-2-ash1-iad -n dependency-graph-api-production delete pod extract-pypi-packages-27891120-xnpj4
```

Now, we have two choices to resolve the incident:
1. **Automated**: redeploy the `workers` from Slack chatops: `.deploy dependency-graph-api/master to workers` and await the next cron run
1. **Manual**: hop back into a `scripts` pod and try to kick off another run (see above) - if successful, redeploy `workers` anyway to replace the missing pod
