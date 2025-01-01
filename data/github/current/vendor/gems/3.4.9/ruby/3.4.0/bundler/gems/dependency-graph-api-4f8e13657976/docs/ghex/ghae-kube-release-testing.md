## GHAE Release Testing

**IMPORTANT**: the 3.6 GHAE release is slated to be the _final release cycle_ for the product :tada: so if all goes well, this reference material can be deprecated and eliminated when the product is fully EOL. Plans change, so we should keep this material around for now :+1:

Review the [general GHAE development instructions](./ghae-dev-instructions.md) here; a development env and instance should only be required if you encounter and need to debug problems in a release branch.

### Testing
* You'll start out using the "gh-staffship" release testing shared instance at: `https://github.ghe.com`
    * ^ confirm this flow hasn't changed since last release (review your sign-off Issue)
* Login for access with `gh auth login` and hostname `github.ghe.com` and follow prompts
* Access Geneva logs from the staff testing instance [using this doc](https://github.com/github/ops/blob/master/docs/playbooks/ghae/service-logs.md)
    * Note: if asked for 2FA auth, choose Azure Active Directory (will require `@microsoft` login)
    * We have SEVERAL LOG NAMESPACES in Geneva to monitor:
        * DG-API: `GHDependencyGraphApi`
        * Aqueduct worker(s): `GHDependencyGraphApiAqueductWorker`
        * General bootstrapping? `GHDepGraphSetup`
* `kubectl`:
    * `ghae` (one blanket k8s namespace for all)
    * Replica Sets in namespace:
        * `dependency-graph-api` (DG-API service)
        * `dependency-graph-aqueduct-worker` (Aqueduct worker pool)
        * `dependency-graph-manifest-file-{changed,deleted}` (Hydro consumers)

### Bootstrapping a Dev Instance
Accessing a shared release instance when release testing fails requires a SAW machine and elaborate MSFT access. If the service logs don't definitively surface the problem _and_ solution in the release env, you will need to spin up your own _dev instance_ and _reproduce the fail_ to debug with full access. That process is described below:

1. In `#ghae-rp-chatops` or `#dg-ops`, run the chatop: `.ghae boot branch=enterprise-*-release`, substituting your target release branch/GHAE version
1. The chatop should respond with a link to an Actions workflow run on `ghae-kube` repo called "Provision and Deploy"
1. This will run a while; In the meantime, spin up a new `ghae-kube` codespace: `gh cs create -r github/ghae-kube`
1. When the Action is complete, check in the logs under "Step 7" section (near the end) for the URL of your instance. Example: `[2023-01-20 20:39:37.382] INFO To access the UI, you can access https://ghaedev-3970148431-main-2.ghaekube.net`
1. Browse to the URL from the logs; at the GitHubAE Login landing page, login w/user `ghae-admin` and pass: `passworD1`
1. Completion of the Action will also trigger the chatop to reply with a JSON object; copy it to your clipboard
1. Log into the codespace using `gh cs ssh` (select the `ghae-kube` instance)
1. Copy the JSON object into a file in the repo root of the `ghae-kube` codespace checkout; call it `config.json`
1. In the repo checkout root, run `script/bootstrap`
1. Next, execute: `az login --use-device-code`
1. If bootstrap and Azure login is successfully, run `script/ci-connect -c config.json -v` to obtain a CLI session on the backing k8s cluster


### Links
Handy links since the docs and config/functionality are spread across multiple repositories for GHAE. **IMPORTANT**: validate you're viewing the _appropriate Enterprise release branch_ for the release your testing, if applicable!
* `ghae-kube` Service deployment specs [here](https://github.com/github/ghae-kube/tree/main/ghae/charts/dependency-graph-api)
* `ghae-kube` Docker image SHAs (including DG version in use!) defined [here](https://github.com/github/ghae-kube/blob/main/shas.yaml)
    * Example from 3.6 release testing: [link](https://github.com/github/ghae-kube/blob/enterprise-3.6-release/shas.yaml#L62-L68)
* Mappings of GHAE replica sets (DG deployments in the `ghae` k8s namespace) are defined [here](https://github.com/github/ghae-monitor/blob/main/ev2/ServiceGroupRoot/Packages/AmeWarmPathConfig/main.xml) TODO [here](https://github.com/github/ghae-monitor/blob/dcf1677f4b0df2df5ce69235bbae1bb9622c00b3/ev2/ServiceGroupRoot/Packages/AmeWarmPathConfig/main.xml#L346-L357)
    * ^ PLEASE update the above whenever we add a new replicaset/deployment to our GHAE footprint
* Shared instance logs are pushed to Geneva and the stream + filters are accessible in Jarvis [here](https://github.com/github/ops/blob/master/docs/playbooks/ghae/service-logs.md):
    * ^ Requires `@microsoft.com` login to access
    * ^ When prompted for 2FA, select `Azure Active Directory (AAD)` and your MSFT login should get you past this
    * Check _all the filter options_ on the left side pane _before_ attempting log filtering (watch for odd defaults being applied!)
    * Ensure you select _all DG-related namespaces defined in `ghae-monitor` repo_ (linked above) for DG services in GHAE!


