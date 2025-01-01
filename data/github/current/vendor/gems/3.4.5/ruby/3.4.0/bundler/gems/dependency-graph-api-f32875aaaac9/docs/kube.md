# Operating & Maintaining Dependency Graph in Kubernetes

This document outlines our Kubernetes deployment, roles and useful resources.

- [Shell](#shell)
- [Kubernetes Environments](#kubernetes-environments)
  - [Dotcom](#dotcom)
    - [API](#api)
      - [Deployments](#deployments)
    - [Workers](#workers)
      - [Cronjobs](#cronjobs)
      - [Deployments](#deployments-1)
  - [Proxima](#proxima)
- [Tips \& Tricks](#tips--tricks)
  - [File Transferring](#file-transferring)


Our deployments are as follows:

| Role | Namespace | Clusters |
| ---- | --------- | -------- |
| API | dependency-graph-api-production | general-{1,2,3}-{ash1, ac4, va3}-iad |
| Workers | dependency-graph-api-production | general-{1,2,3}-{ash1, ac4, va3}-iad  |
| Shell | dependency-graph-api-shell | general-{1,2,3}-{ash1, ac4, va3}-iad  |
| Scripts | dependency-graph-api-scripts | general-{1,2,3}-{ash1, ac4, va3}-iad  |

### Some useful links in Kubernetes documentation
* [ Application Introspection and Debugging
](https://kubernetes.io/docs/tasks/debug-application-cluster/)
* [Running Automated Tasks with a CronJob](https://kubernetes.io/docs/tasks/job/automated-tasks-with-cron-jobs/)
* [Debugging Pods](https://kubernetes.io/docs/tasks/debug-application-cluster/debug-pod-replication-controller/#debugging-pods)

## Shell

As part of our Kubernetes deployment, we run a special `shell` role that is booted up with the same environment as the rest of the app and is accessible from the ops shell machines. You can use this shell host to debug failing components or try running commands from cron jobs manually to troubleshoot failures.

1. Log in to a bastion ops shell host. Instructions on setting up your `ssh_config` are [here](https://thehub.github.com/engineering/security/production-shell-access/#shell-and-other-applications)

``` bash
$ ssh shell
```

2. On the shell host, log in to vault (requires password/2FA challenge).
   We source the script because it sets `VAULT_TOKEN` in the shell's environment.

``` bash
$ source vault-login
```

3. Run [`gh-kubeconfig`](https://github.com/github/moda/blob/main/team-docs/debugging-with-kubectl.md#setting-up-your-kubectl-credentials) with the name of a Moda (Kubernetes) cluster to mark
   it as your current cluster.
   To display the currently selected cluster, run the command with no arguments,
   but beware that the list of other clusters it displays may contain stale entries.
   To list currently available clusters, run `gh-k8s-clusters --status ready --profile general`,
   or use the [Moda view](https://moda.githubapp.com/apps/dependency-graph-api/).

```bash
$ gh-kubeconfig general-3-ac4-iad
...
CURRENT   NAME                 CLUSTER              AUTHINFO                    NAMESPACE
          general-1-ash1-iad   general-1-ash1-iad   general-1-ash1-iad-heaven
*         general-2-ac4-iad    general-2-ac4-iad    general-2-ac4-iad-heaven
          general-2-va3-iad    general-2-va3-iad    general-2-va3-iad-heaven
...
```

4. Get the running pods for the `dependency-graph-api-shell` namespace.

``` bash
$ kubectl get pods -n dependency-graph-api-shell
```

**Sample Output**
``` bash
kubectl get pods -n dependency-graph-api-shell
NAME                    READY   STATUS    RESTARTS   AGE
shell-fcff8bc97-tsfz8   1/1     Running   0          23h
```

5. You can log into the `shell` pod to run commands.
   This puts you in a shell inside the docker container running the production service.
   Tread with care!

``` bash
$ kubectl exec -itn dependency-graph-api-shell shell-fcff8bc97-tsfz8 -- bash
```

6. Profit!

## Kubernetes Environments
### Dotcom
#### API
##### Deployments
| Role | Kube Config | Splunk | Datadog  | Sentry |
|:----|:---:|:---:|:---:|:---:|
| **api** | [Source](../config/kubernetes/api/deployments/api.yaml)  | [Logs](https://splunk.githubapp.com/en-US/app/gh_reference_app/search?q=search%20index%3Ddependency-graph-api%20kube_namespace%3D%22dependency-graph-api-production%22%20host%3D%22api-*%22&display.page.search.mode=smart&dispatch.sample_ratio=1&earliest=-7d%40h&latest=now) | [Dashboard](https://app.datadoghq.com/dashboard/cmd-vkt-mii/dg-api) | [Exceptions](https://sentry.io/organizations/github/issues/?environment=api&project=1858608&query=is%3Aunresolved+url%3Ahttps%3A%2F%2Fdependency-graph-api.service.iad.github.net%2Fquery&statsPeriod=14d) |
| **slow-query-api** | [Source](../config/kubernetes/api/deployments/slow-query-api.yaml)| [Logs](https://splunk.githubapp.com/en-US/app/gh_reference_app/search?q=search%20index%3Ddependency-graph-api%20kube_namespace%3D%22dependency-graph-api-production%22%20host%3D%22slow-query-api-*%22&display.page.search.mode=smart&dispatch.sample_ratio=1&earliest=-7d%40h&latest=now) | [Dashboard](https://app.datadoghq.com/dashboard/aki-76m-wgi/dg-slow-query-api) | [Exceptions](https://sentry.io/organizations/github/issues/?environment=api&project=1858608&query=is%3Aunresolved+url%3Ahttps%3A%2F%2Fdependency-graph-api-slow-queries.service.iad.github.net%2Fquery&statsPeriod=14d) |

APIs have load balancer services defined [here](https://github.com/github/dependency-graph-api/tree/master/config/kubernetes/api/services)

#### Workers
##### Cronjobs
| Role | Kube Config | Splunk | Datadog  | Sentry |
|:----|:---:|:---:|:---:|:---:|
|**workers**||||[Exceptions](https://sentry.io/organizations/github/issues/?environment=workers&project=1858608&query=is%3Aunresolved&statsPeriod=14d)|
| **abstract_dependent_counts** |  [Source](../config/kubernetes/workers/cronjobs/abstract_dependent_counts.yaml) | [Logs](https://splunk.githubapp.com/en-US/app/search/search?q=search%20index%3D%22dependency-graph-api%22%20kube_namespace%3Ddependency-*%20host%3D%22abstract-dependent-counts-*%22&earliest=%40d&latest=now&display.page.search.mode=smart&dispatch.sample_ratio=1&display.page.search.tab=events&display.general.type=events&sid=1543590716.144947_3F5C36BA-BDF8-49A3-867F-5B90BF43AFDA) | | |
| **sync_vulnerabilities** |  [Source](../config/kubernetes/workers/cronjobs/sync_vulnerabilities.yaml) | [Logs](https://splunk.githubapp.com/en-US/app/search/search?q=search%20index%3D%22dependency-graph-api%22%20kube_namespace%3Ddependency-*%20host%3D%22sync-vulnerabilities-*%22&earliest=%40d&latest=now&display.page.search.mode=smart&dispatch.sample_ratio=1&display.page.search.tab=events&display.general.type=events&sid=1543590716.144947_3F5C36BA-BDF8-49A3-867F-5B90BF43AFDA) | | |
| **extract_ruby_packages** | [Source](../config/kubernetes/workers/cronjobs/extract_ruby_packages.yaml) | [Logs](https://splunk.githubapp.com/en-US/app/search/search?q=search%20index%3D%22dependency-graph-api%22%20kube_namespace%3Ddependency-*%20host%3D%22extract-ruby-packages-*%22&earliest=%40d&latest=now&display.page.search.mode=smart&dispatch.sample_ratio=1&display.page.search.tab=events&display.general.type=events&sid=1544728654.3693_3F5C36BA-BDF8-49A3-867F-5B90BF43AFDA)  | [Graph](https://app.datadoghq.com/dashboard/9im-uhe-hwd/dg-package-manager-adapters?fullscreen_end_ts=1624568467698&fullscreen_paused=false&fullscreen_section=overview&fullscreen_start_ts=1624554067698&fullscreen_widget=8213785767296170&from_ts=1624553973541&to_ts=1624568373541&live=true) | |
| **extract_maven_packages** |   [Source](../config/kubernetes/workers/cronjobs/extract_maven_packages.yaml)  | [Logs](https://splunk.githubapp.com/en-US/app/search/search?q=search%20index%3D%22dependency-graph-api%22%20kube_namespace%3Ddependency-*%20host%3D%22extract-maven-packages-*%22&earliest=%40d&latest=now&display.page.search.mode=smart&dispatch.sample_ratio=1&display.page.search.tab=events&display.general.type=events&sid=1543590716.144947_3F5C36BA-BDF8-49A3-867F-5B90BF43AFDA)  | [Graph](https://app.datadoghq.com/dashboard/9im-uhe-hwd/dg-package-manager-adapters?fullscreen_end_ts=1624568497234&fullscreen_paused=false&fullscreen_section=overview&fullscreen_start_ts=1624554097234&fullscreen_widget=5415397554323098&from_ts=1624553973541&to_ts=1624568373541&live=true) | |
| **extract_nuget_packages** |   [Source](../config/kubernetes/workers/cronjobs/extract_nuget_packages.yaml) | [Logs](https://splunk.githubapp.com/en-US/app/search/search?q=search%20index%3D%22dependency-graph-api%22%20kube_namespace%3Ddependency-*%20host%3D%22extract-nuget-packages-*%22&earliest=%40d&latest=now&display.page.search.mode=smart&dispatch.sample_ratio=1&display.page.search.tab=events&display.general.type=events&sid=1543590716.144947_3F5C36BA-BDF8-49A3-867F-5B90BF43AFDA) | [Graph](https://app.datadoghq.com/dashboard/9im-uhe-hwd/dg-package-manager-adapters?fullscreen_end_ts=1624568512187&fullscreen_paused=false&fullscreen_section=overview&fullscreen_start_ts=1624554112187&fullscreen_widget=7892049023858875&from_ts=1624553973541&to_ts=1624568373541&live=true) | |
| **extract_composer_packages** |   [Source](../config/kubernetes/workers/cronjobs/extract_composer_packages.yaml) | [Logs](https://splunk.githubapp.com/en-US/app/search/search?q=search%20index%3D%22dependency-graph-api%22%20kube_namespace%3Ddependency-*%20host%3D%22extract-composer-packages-*%22&earliest=%40d&latest=now&display.page.search.mode=smart&dispatch.sample_ratio=1&display.page.search.tab=events&display.general.type=events&sid=1543590716.144947_3F5C36BA-BDF8-49A3-867F-5B90BF43AFDA) | [Graph](https://app.datadoghq.com/dashboard/9im-uhe-hwd/dg-package-manager-adapters?fullscreen_end_ts=1624568528747&fullscreen_paused=false&fullscreen_section=overview&fullscreen_start_ts=1624554128747&fullscreen_widget=112351440886012&from_ts=1624553973541&to_ts=1624568373541&live=true)| |
| **extract_pypi_packages** | [Source](../config/kubernetes/workers/cronjobs/extract_pypi_packages.yaml) | [Logs](https://splunk.githubapp.com/en-US/app/search/search?q=search%20index%3D%22dependency-graph-api%22%20kube_namespace%3Ddependency-*%20host%3D%22extract-pypi-packages-*%22&earliest=%40d&latest=now&display.page.search.mode=smart&dispatch.sample_ratio=1&display.page.search.tab=events&display.general.type=events&sid=1543590716.144947_3F5C36BA-BDF8-49A3-867F-5B90BF43AFDA) | [Graph](https://app.datadoghq.com/dashboard/9im-uhe-hwd/dg-package-manager-adapters?fullscreen_end_ts=1624568377878&fullscreen_paused=false&fullscreen_section=overview&fullscreen_start_ts=1624553977878&fullscreen_widget=4459770134296096&from_ts=1624553973541&to_ts=1624568373541&live=true) | |

##### Deployments
| Role | Kube Config | Splunk | Datadog  | Sentry |
|:----|:---:|:---:|:---:|:---:|
|**workers**||||[Exceptions](https://sentry.io/organizations/github/issues/?environment=workers&project=1858608&query=is%3Aunresolved&statsPeriod=14d)|
| **repository-deleted** |  [Source](../config/kubernetes/workers/deployments/repository_deleted.yaml) | [Logs](https://splunk.githubapp.com/en-US/app/search/search?q=search%20index%3D%22dependency-graph-api%22%20kube_namespace%3Ddependency-*%20host%3D%22repository-deleted-*%22&earliest=%40d&latest=now&display.page.search.mode=smart&dispatch.sample_ratio=1&display.page.search.tab=events&display.general.type=events&sid=1543590716.144947_3F5C36BA-BDF8-49A3-867F-5B90BF43AFDA) | [Ingest Dash](https://app.datadoghq.com/dashboard/rb9-x9p-b8f/simple-ingest-dash?is_auto=false&page=0&tile_size=l&from_ts=1624564733704&to_ts=1624568333704&live=true) | |
| **ingest-packages** | [Source](../config/kubernetes/workers/deployments/ingest_packages.yaml) | [Logs](https://splunk.githubapp.com/en-US/app/search/search?q=search%20index%3D%22dependency-graph-api%22%20kube_namespace%3Ddependency-*%20host%3D%22ingest-packages-*%22&earliest=%40d&latest=now&display.page.search.mode=smart&dispatch.sample_ratio=1&display.page.search.tab=events&display.general.type=events&sid=1544740094.7033_3F5C36BA-BDF8-49A3-867F-5B90BF43AFDA) | [Ingest Dash](https://app.datadoghq.com/dashboard/rb9-x9p-b8f/simple-ingest-dash?is_auto=false&page=0&tile_size=l&from_ts=1624564733704&to_ts=1624568333704&live=true) | |
| **repo-manifest-file-changes** |  [Source](../config/kubernetes/workers/deployments/repo_manifest_file_changes.yaml) | [Logs](https://splunk.githubapp.com/en-US/app/search/search?q=search%20index%3D%22dependency-graph-api%22%20kube_namespace%3Ddependency-*%20host%3D%22repo-manifest-file-changes-*%22&earliest=%40d&latest=now&display.page.search.mode=smart&dispatch.sample_ratio=1&display.page.search.tab=events&display.general.type=events&sid=1543590716.144947_3F5C36BA-BDF8-49A3-867F-5B90BF43AFDA) | [Ingest Dash](https://app.datadoghq.com/dashboard/rb9-x9p-b8f/simple-ingest-dash?is_auto=false&page=0&tile_size=l&from_ts=1624564733704&to_ts=1624568333704&live=true) | |
| **repo-manifest-file-deleted** |  [Source](../config/kubernetes/workers/deployments/repo_manifest_file_deleted.yaml) | [Logs](https://splunk.githubapp.com/en-US/app/search/search?q=search%20index%3D%22dependency-graph-api%22%20kube_namespace%3Ddependency-*%20host%3D%22repo-manifest-file-deleted-*%22&earliest=%40d&latest=now&display.page.search.mode=smart&dispatch.sample_ratio=1&display.page.search.tab=events&display.general.type=events&sid=1543590716.144947_3F5C36BA-BDF8-49A3-867F-5B90BF43AFDA) | [Ingest Dash](https://app.datadoghq.com/dashboard/rb9-x9p-b8f/simple-ingest-dash?is_auto=false&page=0&tile_size=l&from_ts=1624564733704&to_ts=1624568333704&live=true) | |
| **repo-visibility-changes** |  [Source](../config/kubernetes/workers/deployments/repo_visibility_changes.yaml) | [Logs](https://splunk.githubapp.com/en-US/app/search/search?q=search%20index%3D%22dependency-graph-api%22%20kube_namespace%3Ddependency-*%20host%3D%22repo-visibility-changes-*%22&earliest=%40d&latest=now&display.page.search.mode=smart&dispatch.sample_ratio=1&display.page.search.tab=events&display.general.type=events&sid=1543590716.144947_3F5C36BA-BDF8-49A3-867F-5B90BF43AFDA) | [Ingest Dash](https://app.datadoghq.com/dashboard/rb9-x9p-b8f/simple-ingest-dash?is_auto=false&page=0&tile_size=l&from_ts=1624564733704&to_ts=1624568333704&live=true) | |
| **extract-npm-packages** | [Source](../config/kubernetes/workers/deployments/extract_npm_packages.yaml) | [Logs](https://splunk.githubapp.com/en-US/app/search/search?q=search%20index%3D%22dependency-graph-api%22%20kube_namespace%3Ddependency-*%20host%3D%22extract-npm-packages-*%22&earliest=%40d&latest=now&display.page.search.mode=smart&dispatch.sample_ratio=1&display.page.search.tab=events&display.general.type=events&sid=1543590716.144947_3F5C36BA-BDF8-49A3-867F-5B90BF43AFDA) | [Graph](https://app.datadoghq.com/dashboard/9im-uhe-hwd/dg-package-manager-adapters?fullscreen_end_ts=1624568538665&fullscreen_paused=false&fullscreen_section=overview&fullscreen_start_ts=1624554138665&fullscreen_widget=8339813014001802&from_ts=1624553973541&to_ts=1624568373541&live=true) | |
| **extract_go_packages** |   [Source](../config/kubernetes/workers/deployments/extract_go_packages.yaml) | [Logs](https://splunk.githubapp.com/en-US/app/search/search?q=search%20index%3D%22dependency-graph-api%22%20kube_namespace%3Ddependency-*%20host%3D%22extract-go-packages-*%22&earliest=%40d&latest=now&display.page.search.mode=smart&dispatch.sample_ratio=1&display.page.search.tab=events&display.general.type=events&sid=1543590716.144947_3F5C36BA-BDF8-49A3-867F-5B90BF43AFDA) | [Graph](https://app.datadoghq.com/dashboard/9im-uhe-hwd/dg-package-manager-adapters?fullscreen_end_ts=1624568549553&fullscreen_paused=false&fullscreen_section=overview&fullscreen_start_ts=1624554149553&fullscreen_widget=6523123753753628&from_ts=1624553973541&to_ts=1624568373541&live=true) | |

Note: Actions does not have a cron job/deployment for it's package manager adapter. When a manifest is ingested, the [ActionsPackageJob](../app/jobs/actions_package_job.rb) is run for all package releases.

### Proxima

| Stamp | Role | Splunk |
| ----- | ----- | -------- |
| staff-wus2-01 |  api | [Logs](https://splunk.githubapp.com/en-GB/app/search/search?dispatch.sample_ratio=1&display.page.search.mode=fast&q=search%20index%3Ddependency-graph-api%20kube_namespace%3D%22dependency-graph-api-staff-wus2-01%22%20host%3D%22api-*%22%20stamp%3Dstaff-wus2-01&earliest=-15m%40m&latest=now) |
| |  slow-query-api | [Logs](https://splunk.githubapp.com/en-GB/app/search/search?dispatch.sample_ratio=1&display.page.search.mode=fast&q=search%20index%3Ddependency-graph-api%20kube_namespace%3D%22dependency-graph-api-staff-wus2-01%22%20host%3D%22slow-query-api-*%22%20stamp%3Dstaff-wus2-01&earliest=-15m%40m&latest=now) |
| |  aqueduct-resqued-worker | [Logs](https://splunk.githubapp.com/en-GB/app/search/search?dispatch.sample_ratio=1&display.page.search.mode=fast&q=search%20index%3Ddependency-graph-api%20kube_namespace%3D%22dependency-graph-api-staff-wus2-01%22%20host%3D%22aqueduct-resqued-worker-*%22&earliest=-7d%40h&latest=now) |
| |  repo-archived-status-changes | [Logs](https://splunk.githubapp.com/en-GB/app/search/search?dispatch.sample_ratio=1&display.page.search.mode=fast&q=search%20index%3Ddependency-graph-api%20kube_namespace%3D%22dependency-graph-api-staff-wus2-01%22%20host%3D%22repo-archived-status-changes-*%22&earliest=-7d%40h&latest=now) |
| |  repo-manifest-file-changes | [Logs](https://splunk.githubapp.com/en-GB/app/search/search?dispatch.sample_ratio=1&display.page.search.mode=fast&q=search%20index%3Ddependency-graph-api%20kube_namespace%3D%22dependency-graph-api-staff-wus2-01%22%20host%3D%22repo-manifest-file-changes-*%22&earliest=-7d%40h&latest=now) |
| |  repo-manifest-file-deleted | [Logs](https://splunk.githubapp.com/en-GB/app/search/search?dispatch.sample_ratio=1&display.page.search.mode=fast&q=search%20index%3Ddependency-graph-api%20kube_namespace%3D%22dependency-graph-api-staff-wus2-01%22%20host%3D%22repo-manifest-file-deleted-*%22&earliest=-7d%40h&latest=now) |
| |  repository-deleted | [Logs](https://splunk.githubapp.com/en-GB/app/search/search?dispatch.sample_ratio=1&display.page.search.mode=fast&q=search%20index%3Ddependency-graph-api%20kube_namespace%3D%22dependency-graph-api-staff-wus2-01%22%20host%3D%22repository-deleted-*%22&earliest=-7d%40h&latest=now) |
| |  sync-vulnerabilities | [Logs](https://splunk.githubapp.com/en-GB/app/search/search?dispatch.sample_ratio=1&display.page.search.mode=fast&q=search%20index%3Ddependency-graph-api%20kube_namespace%3D%22dependency-graph-api-staff-wus2-01%22%20host%3D%22sync-vulnerabilities-*%22&earliest=-15m%40m&latest=now) |



## Tips \& Tricks

### File Transferring

If you want to move files from a kube pod to your local computer, do the following:

On a production shell, run the following command to move files from a kube pod to your shell’s working directory.

```
kubectl cp <namespace_name>/<pod_name>:<file_path_in_application>  <dir_on_shell>
```

Move the files from your shell to your computer with the following command, if you have [`ssh shell`/proxy jump](https://thehub.github.com/engineering/security/production-shell-access/#shell-and-other-applications) set up.

```
scp -r shell:<dir_on_shell> <dir_on_computer>
```

To do the reverse, simple reverse the commands and directory direction!

```
scp -r <dir_on_computer> shell:<dir_on_shell>
```

```
kubectl cp <dir_on_shell>  <namespace_name>/<pod_name>:<file_path_in_application>
```
