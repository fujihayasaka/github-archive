# Overview
## What is...?

Collectively known as GHEX, GitHub Enterprise has a few names and flavors. Below are the basics:

- GHES: GitHub Enterprise Server, which is the on-prem solution.
    - Oldest non-dotcom enterprise solution.
    - Most customers and support issues we interact with will be on GHES, so this is the platform to become the most comfortable with first!
    - Last year, it was transitioned to a more containerized solution, so in a way it's structurally quite similar to GHAE now.
- GHAE: is a new Azure-powered hosted sandbox Enterprise installation
    - Quite new, as we started working with it in 2021.
- GHEC: GitHub Enterprise Cloud, which is just a plan on dotcom and doesn't use the `github/enterprise2` repository.
## Architectural Differences
### GHEC

- Dotcom, with gated logic included enterprise only features.
- Production dg-api experience. K8s configuration, deployments and cronjobs managed by Moda.

Dotcom logic flag: `GitHub.enterprise?`

### GHES & GHAE

:exclamation: No development feature flags in enterprise!!

#### **Enablement:**
- GHES: Dependency Graph is not enabled by default. It must be enabled via the Management Console.
- GHAE: Dependency Graph is enabled by default.

#### **Dotcom logic flags:**
- GHES only: `GitHub.enterprise? && GitHub.single_business_environment?`
- GHAE only: `GitHub.enterprise? && GitHub.private_instance?`

#### **Dependency graph quirks:**
- There are no package manager adapters, and thus there is no package metadata.
  - This means no:
    - package-to-repo mapping
    - sub dependencies on repo insights package
    - org dependency insights
    - license data

#### **Dependabot alerts:**
 - In order for Dependabot Alerts to function, we need to fetch existing and future advisories from AdvisoryDB.
 - We are only able to pull data from the outside world via GitHub Connect, which connects to an Enterprise or Enterprise Org on dotcom.
   - Steps for setting up GitHub Connect are documented [here](./dependency_graph_in_ghes.md#setting-up-gh-connect).
- Both GHAE and GHES need this for alerts. Dependency graph **does not** need this to function on it's on.

#### **K8s management:**

We have 4 containers that are both on GHES & GHAE:
 - `dependency-graph-api-service`
 - `dependency-graph-api-aqueduct-worker`
 - `dependency-graph-api-processor-manifest-file-changed-worker`
 - `dependency-graph-api-processor-manifest-file-deleted-worker`

There are difference in how they are managed and configured though:
- GHES
  - Containers are managed by the Nomad orchestrator. They are deployed as nomad jobs you can interact with.
  - Our deployment configurations are defined in Consul templates [here](https://github.com/github/enterprise2/blob/master/vm_files/etc/consul-templates/etc/nomad-jobs/dependency-graph-api/).
  - There is also one additional job/container: `dependency-graph-api-dispatch`
    - It is a [parameterized](https://learn.hashicorp.com/tutorials/nomad/job-spec-parameterized?in=nomad/job-specifications) nomad job, meaning it only runs when it's invoked with specific params to act on.
    - At the moment, the only place it is currently utilized is in the GHES [migration script](https://github.com/github/enterprise2/blob/master/vm_files/usr/local/share/enterprise/ghe-run-migrations).
- GHAE
  - You can manage containers through the very familiar kube tooling, a la `kubectl`.
  - Our deployment configurations are defined in Helm chart templates [here](https://github.com/github/ghae-kube/tree/main/ghae/charts/dependency-graph-api/templates).
- From there, with the right environment variables for things like Spokes, Redis, Aqueduct...things should talk to each other as expected!

#### **Service to service communication:**
- GraphQL: same as dotcom!
- Aqueduct: new to our service and same as dotcom!
  - We should continue to use this more.
- Twirp: same as dotcom!
- Hydro
    - Things are different here.
    - Hydro is very memory/space intensive, so in place of that `kafka-lite` is used.
      - `kakfa-lite` is not actually real zookeeper/kafka, but instead uses a redis store.
    - Disk, memory, and CPU are very valuable on these enterprise solutions. That means by default, all hydro topics are disabled and have to be enabled manually.
        - GHES topics are defined [here](https://github.com/github/hydro-schemas/blob/main/topic-configuration/production/enterprise/github.yaml).
        - GHAE topics are defined [here](https://github.com/github/ghae-kube/blob/main/ghae/charts/kafka-lite/templates/configmap.yaml).
    - We currently have two topics enabled in order to enable manifest ingestion:
     - `cp1-iad.ingest.github.dependencygraph.v1.RepositoryManifestFileChange`
     - `cp1-iad.ingest.github.dependencygraph.v0.RepositoryManifestFileDelete`

## **What development environment do I use?**
- GHEC: Regular dotcom
- GHES
  - Do you want to edit services and config? `bp-dev` [(docs)](https://github.com/github/dependency-graph-api/blob/master/docs/ghex/bp-dev.md)
  - If you just want to boot up and instance to check in on an existing public or QA release, use `gheboot` [(docs)](https://github.com/github/dependency-graph-api/blob/master/docs/ghex/dependency_graph_in_ghes.md#using-dependency-graph-with-gheboot)
- GHAE
  - For development, you need to use `ghae-kube` [(docs)](https://github.com/github/dependency-graph-api/blob/master/docs/ghex/ghae-kube-dev-instructions.md)
  - If you just want to check in on a staff-shipped GHAE instance, visit https://github.ghe.com/
## Release Schedule

For the enterprise release schedule, you can find that in the [enterprises-releases](https://github.com/github/enterprise-releases/blob/master/releases.json) repository. You can also run the `.ghe release-dates` chatop for a quick at-a-glance summary.
