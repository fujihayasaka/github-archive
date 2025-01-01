# Enterprise Debugging

**Stop! Before you dive into debugging...**

Have you:
- Primed yourself with general enterprise knowledge over at our [overview doc](https://github.com/github/dependency-graph-api/blob/master/docs/ghex/overview.md)?
- Setup the appropriate development environment using our handy documentation?
  - [`bp-dev`](https://github.com/github/dependency-graph-api/blob/master/docs/ghex/bp-dev.md) for GHES
  - [`ghae-kube`](https://github.com/github/dependency-graph-api/blob/master/docs/ghex/ghae-kube-dev-instructions.md) for GHAE

Then you may proceed.

:spiral_notepad: If you have nuggets of information/debugging tips during enterprise work, this would be a good place to jot them down!

<!-- TODO: double check deploy enterprise change command -->
## Quick commands:

| Need | GHES | GHAE |
| -----|:----:| :---:|
| dg-api logs | `journalctl -ft dependency-graph-api`| `kubectl logs deployments/dependency-graph-api -c dependency-graph-api --follow [--tail=50]`|
| github-unicorn logs | `github-env`<br>`tail -f log/unicorn.log`| `kubectl logs deployments/github-unicorn -c unicorn --follow [--tail=50]`|
| aqueduct logs | `journalctl -ft dependency-graph-api-aqueduct-worker` | `kubectl logs deployments/dependency-graph-api-aqueduct-worker -c dependency-graph-api-aqueduct-worker --follow [--tail=50]`|
| dg-api console | `nomad exec -job dependency-graph-api-service script/console`| `kubectl exec -it -c dependency-graph-api deployments/dependency-graph-api -- script/console`|
| github console | `github-env`<br>`bin/rails c`| `script/console`|
| testing a fix in dg-api or `github/github` | [docs](https://github.com/github/dependency-graph-api/blob/master/docs/ghex/dependency_graph_in_ghes.md#dependency-graph-api) | [docs](https://github.com/github/dependency-graph-api/blob/master/docs/ghex/ghae-kube-dev-instructions.md#developing-services-for-ghae-kube)|
| testing a change made in enterprise | `./chroot-stop.sh`<br>`./chroot-build.sh`<br>`./chroot-start.sh`<br>`./chroot-configure.sh` | `./script/setup --no-provision --deploy -g sarahkemi`|

## Support Logging:

### **GHES**
Tips and locations of dg-api specific logs in support bundles can be found [here](https://github.com/github/dependency-graph-api/blob/master/docs/ghex/dependency_graph_in_ghes.md#using-support-bundle-logs)

### **GHAE**

General documentation for logging in GHAE can be found on [The Hub](https://thehub.github.com/epd/engineering/products-and-services/ghae/production/observability/logging/)

You can find links to Geneva dashboards for all services in this [playbook](https://github.com/github/ops/blob/master/docs/playbooks/ghae/service-logs.md). We have logs under `Dependency Graph Setup` and `Dependency-graph-api`.

Tip: You'll find customer/prod logs under the `Diagnostics PROD` endpoint, and dev logs under `Test`.

In Geneva, you can change `Tenant` to the GHAE instance you are debugging!

## Common scenario types

### **Build/container issues**

- This is less of an issue now that we’ve combined our dockerfiles into a multi-step one.
- You can find enterprise specific build steps in our [Dockerfile's](https://github.com/github/dependency-graph-api/blob/master/Dockerfile) `run-enterprise` target.
- Have any new dependencies been added to dg-api that require special compiling? Make sure they’re built in earlier stages, especially if they’re in a directory that will be removed from the application before it’s copied over into the image that customers will have on their enterprise installation.

### **Migrations**

**GHES only**

If migrations are failing, but you check our logs and don’t see anything migration related, errors are most likely occurring in the [dispatch script](https://github.com/github/enterprise2/blob/master/vm_files/usr/local/bin/dependency-graph-api-env-dispatch).

### **Service to service communications**

Moving to Aqueduct and Spokes helps a lot here.

- Common issue: not having our env vars wired up to correct service URLs and databases in our service's deployment config.
- Checking dg-api, dotcom, and aqueduct logs will go a long way. See above for a cheatsheet.
- If we’ve created new Hydro topics in production, you’ll need to enable them in both GHES and GHAE. Topic definition locations documented [here](https://github.com/github/dependency-graph-api/blob/master/docs/ghex/overview.md#service-to-service-communication).
- If we’ve created a new Moda deployment in production, those same deployments will need to be created in `enterprise2` (GHES) and `ghae-kube`.
- Make sure that all UX on dotcom that uses dg-api is gated by a check to ensure dependency graph is enabled and available (`GitHub.dependency_graph_enabled?`).

### **UI**
- Customers can be confused when the messaging isn't specific to their enterprise type, and in some cases access parts of our products that aren't yet available on their enterprise type/version.
- Use [appropriate conditionals](https://github.com/github/dependency-graph-api/blob/master/docs/ghex/overview.md#dotcom-logic-flags) in `github/github` to gate logic.

### **DG-API enablement**

#### GHES

Ways to configure:

- Through the Management Console UI
- Using `ghe-dep-graph-enable` to enable
  - Under the hood this runs `ghe-config "app.dependency-graph.enabled" true` and `ghe-config-apply`.
    - You can run those commands manually. You can also set it to `false` to turn dg-api off.
    - You can run `ghe-config --get app.dependency-graph.enabled` to see the current value
- Running `chroot-configure`
  - set the dg-api enablement env var using `export ENABLE_DEPENDENCY_GRAPH=1`, and then run `./chroot-configure.sh`
#### GHAE

Enabled by default, so it's sort of hard to disable/re-enable. Proceed with caution!

- On your dev instance, change the `dependency-graph-api` parameter in `ghae-kube` [here](https://github.com/github/ghae-kube/blob/main/ghae/values.yaml).
- Run `script/setup`

### **Updating service SHAS**

GHES docs [here](https://github.com/github/dependency-graph-api/blob/master/docs/ghex/dependency_graph_in_ghes.md#testing-new-changes-in-ghes)

GHAE docs [here](https://github.com/github/dependency-graph-api/blob/master/docs/ghex/ghae-kube-dev-instructions.md#developing-services-for-ghae-kube)

- For GHES, you'll typically use an action in the respective repo to build the service's image for a given PR. From there you'll run `script/update-service.rb [service] [sha]` on your bp-dev instance to update and re-build as normal.
- For GHAE, It's a little weird.
  - If your SHA of choice has already been merged into the default branch, you can simply run a similar update script as GHES and rebuild
  - If it hasn't been, you'll run the update script, but instead of rebuilding, edit the kube deployment and delete the current pods to force a re-spawn.

You should just read the docs!
