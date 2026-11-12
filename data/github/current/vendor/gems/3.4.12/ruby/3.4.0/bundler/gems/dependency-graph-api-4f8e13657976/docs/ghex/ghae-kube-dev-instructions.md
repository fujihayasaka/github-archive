## Prerequisites

General quick-start docs for GHAE dev can be found [here](https://thehub.github.com/epd/engineering/products-and-services/ghae/development/quick-start/).

:exclamation: Getting GHAE azure access can possibly take awhile. It's advised to attempt to get this out of the way well before you want to dive into your GHAE work!

- Set up Microsoft VPN (do _not_ install CompanyPortal/Intune if you are using a Mac for dev! Ignore all instruction to the contrary!)
    - Install Microsoft [GlobalProtect](https://microsoft.sharepoint.com/sites/Network_Connectivity/SitePages/RemoteAccess/GlobalProtect-Desktop-VPN-app-for-Mac.aspx?web=1) app
    - Add a portal address: `msftvpn-alt.ras.microsoft.com`
    - Connect!
    - **WARNING!** GitHub and MSFT VPN address ranges overlap! Both VPNs should _never_ be active at the same time!
- Ensure you are enrolled in TM-GHAE AzureDevOps:
    - While connected to MSFT VPN, browse `https://myaccess`
    - Follow [these instructions](https://thehub.github.com/engineering/development-and-ops/github-ae/access/#how-to-request-access)
    - Wait for email response
- Set up a new GitHub PAT (if needed) with permissions detailed [here](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry#authenticating-to-the-container-registry)
    - Create under "Legacy PATs"
    - Ensure your new PAT has all the required perms set
      - `repo`
      - `write:packages`
      - `read:org`
    - ENABLE SSO for this PAT when created!
    - test locally: `echo $YOUR_NEW_TOKEN | docker login ghcr.io -u $YOUR_GH_LOGIN --password-stdin` and expect `Login Succeeded` response

:exclamation: In GHAE, note that unlike GHES, Dependency Graph is on by default!

It also might be helpful to create your own test enterprise for enabling GitHub Connect (used for Dependabot Alerts).

## Creating your own test enterprise

In both GHES and GHAE, you will need an enterprise to connect to in order to enable GitHub Connect (which allows us to download advisories to use for Dependabot Alerts). Ask a teammate for an invite to our team enterprise, [Dependency Graph Enterprises](https://github.com/enterprises/dg-enterprises/). See instructions for creating your own [here](./dependency_graph_in_ghes.md#create-an-enterprise)!

## ghae-kube codespaces bootstrap (Recommended)

Codespaces is great! As with our other projects, we should utilize codespaces and the nice prebuilds for development in most scenarios.

See https://thehub.github.com/epd/engineering/products-and-services/ghae/development/quick-start/ for main documentation.

Pro-tip: Deploying `ghae-kube` takes a while! It's very possible your Codespace (and thus your deploy) will die on you, unless you increase your [default codespaces timeout](https://docs.github.com/en/codespaces/customizing-your-codespace/setting-your-timeout-period-for-codespaces)! Essentially you should go to your [codespaces settings](https://github.com/settings/codespaces) and scroll down to "Default Idle Timeout", and increase the value (perhaps to 120 minutes?).


- Essentially, you will add a few new secrets to your codespace secrets, for the `github/ghae-kube` repository.
  - `GHCR_CONTAINER_REGISTRY_PASSWORD`, which is the PAT created up above
  - `GH_GHAE_KUBE_PAT`, also the PAT you created
  - `GHCR_CONTAINER_REGISTRY_SERVER`, which is `ghcr.io`
  - `GHCR_CONTAINER_REGISTRY_USER`, which will be your handle
- Launch a codespace, on the main branch so you can pick a prebuild
  - Don't need to run `script/bootstrap` like you would in regular local dev, the codespace does that for you!
- run `az login --use-device-code` to login to Azure
- `GITHUB_TOKEN=$GH_GHAE_KUBE_PAT script/setup`
  - `--enable-actions` if you need it!
  - Go grab a snack, it'll be several minutes!

## ghae-kube local bootstrap
### Bootstrap GHAE for local dev
- Check out [ghae-kube repo](https://github.com/github/ghae-kube)
- `export GITHUB_TOKEN=$YOUR_NEW_TOKEN`
- Execute `docker login` as above, if logged out of Container Registry
- `script/bootstrap` (use `script/reset` if repeated runs fail)

## general ghae-kube development

### Spin up GHAE instance
- Main Hub docs [here](https://thehub.github.com/engineering/development-and-ops/github-ae/)
- Local dev docs [here](https://thehub.github.com/engineering/development-and-ops/github-ae/development-environment/)
   - `script/setup` runs have _two phases_: "provision" and "deploy" - read up on both
   - :exclamation: If you need Actions enabled (for example, for using our Dependency Review Action), append the setup command with `--enable-actions`.
- `script/setup --resource-group $YOUR_GIHUB_LOGIN` (doc says "MSFT alias" but its a lie!)
- At end of a successful run, your instance URL and user/pass for web login will be logged on the console
- If you require direct SSH access to your new cluster, [see this temporary workaround](https://github.com/github/ghae-kube/blob/main/docs/how-tos/enable-ssh-clone.md)

### Handy commands
- **`./script/setup --no-provision --deploy -g [resource group]` to re-deploy after making ghae-kube changes**
- `kubectl logs deployments/dependency-graph-api -c dependency-graph-api --follow [--tail=50]` for tailing logs
- `kubectl exec -it -c dependency-graph-api deployments/dependency-graph-api -- script/console` for accessing our console
- `kubectl logs deployments/github-unicorn -c unicorn --follow [--tail=50]` for tailing dotcom logs
- `script/console` for accessing the `github/github` console
- `script/teardown --resource-group <resource group name>` to clean up resources and tear down your instance after you're done working!

### Developing services for ghae-kube

#### Merged Changes

If you're testing a `dependency-graph-api` or `github/github` branch that's **been merged** into main branch:

1. `./script/update-images dependency-graph-api/dependency-graph-api:[SHA] -v` on your `ghae-kube` branch
    - If you get to an `az login` prompt and you're in a codespace, it'll likely fail. You can run `az login --use-device-code` to login via a static URL, and then re-run the command you're trying to run.
1. Commit + push that branch up
1. Run `script/setup --resource-group [group]`


#### Unmerged Changes

If you're trying to test a `dependency-graph-api` or `github/github` branch that **hasn't been merged** into a main branch yet, you can try the following:

**Make sure you already have a provisioned instance ready!**

**`dependency-graph-api` (and most other services)**
  1. Create a PR, and ensure that `Build Container` action has run on your desired SHA.
  1. In the action run, open the `Push result to GPR..` fold and copy that `[SHA]@sha256:[SHA256]` tag
  1. Run `./script/update-images dependency-graph-api/dependency-graph-api:[tag] -v` to get the branch's image pushed to ACR
      - If you get to an `az login` prompt and you're in a codespace, it'll likely fail. You can run `az login --use-device-code` to login via a static URL, and then re-run the command you're trying to run.
  1. Keep track of that tag you utilized.
  1. Continue on below

**`github/github`**
  1. Run [this action](https://github.com/github/github/actions/workflows/build_ghae_containers.yaml) on your branch to generate image under `github/github-ghae`
  1. Run `./script/update-images github/github-ghae:[SHA] -v` to easily get the branch's image pushed to ACR
      - If you get to an `az login` prompt and you're in a codespace, it'll likely fail. You can run `az login --use-device-code` to login via a static URL, and then re-run the command you're trying to run.
  1. Keep track of the SHA and digest that's outputted from running `script/update-images`. You'll need it for later steps.
  1. Continue on below

**editing the deployment**

- Discard the updated shas.yml (if you don't, `script/setup` will yell at you later on and you will be confused)
- Next, you will update the k9s config for the image's deployment. Run `kubectl edit deployment/dependency-graph-api`
    - Note: for dotcom changes, you will be editing `deployment/github-unicorn`

(Following is slightly modified from ghae docs)

There are two edits to make:
  - "Change the image pull policy to Always. This is important, since we used latest as the tag in the build, and will re-use it for subsequent builds. Without setting Always, the default is IfNotPresent, and new builds of the image wouldn't come in since the cluster has cached that particular tag."
    - For vim, when editing the deployment you can press `/` to start a search and type `image` to find all instances. You can then type `n` to move forward and `N` to go to the previous instance.
    - For deployments like `github-unicorn`, there will be multiple images defined in the one file!!
      - Updating the images belonging to `unicorn` and `unicorn-assets` should be work for most dotcom testing!
  - Change the image to the one pushed earlier.

Examples:

`image: [registry]/[repo]/[repo tag]:[SHA]@sha256:[SHA256]`

```
  image: ghaedev.azurecr.io/github/dependency-graph-api/dependency-graph-api:[SHA]@sha256:[SHA256]
  imagePullPolicy: Always
```

```
  image: ghaedev.azurecr.io/github/github/github-ghae:[SHA]@sha256:[SHA256]
  imagePullPolicy: Always
```

**restarting the deployment**

- For our service's deployments, delete the pods (not the deployment)
  - `kubectl get pods` to find pods of choosing
  - `kubectl delete pod/[pod name]`
- For more complex deployments (like `github-unicorn`), you will find it beneficial to do a rolling restart of the deployment
    - `kubectl rollout restart deployment/[deployment]`
    - Run `kubectl rollout status deployment/[deployment]` to tail the process.
- Pods should respawn with newest image!! :tada:
  - `kubectl get pods` again for restart status.
- You can run `kubectl describe pod/[name]` to get more information on the pod and verify that the correct image was pulled down.

It's possible you may run into an issue where you have two pods of the same type even after you've deleted the existing pod. You can use the `describe` command and see that it's possibly still using the wrong image. In order to truly banish that old image’s pod, you may need to delete the replicaset that controls it.

- Say you have a troublesome pod, called `dependency-graph-api-5b9866459d-trzdt`.
- The replicaset is that first chunk of the pod name, `dependency-graph-api-5b9866459d`.
- So in order to delete the replica set, you  can run kubectl delete ReplicaSet/`dependency-graph-api-5b9866459d` and that should kill it.


See [these fast image inner loop docs](https://github.com/github/ghae-kube/blob/main/docs/how-tos/fast-image-inner-loop.md) for more information.
### Troubleshooting
- `403 Forbidden` errors: it's your new PAT
    - All the right perms in place?
    - SSO enabled on PAT?
    - `GITHUB_TOKEN` is exported in your local console session w/new PAT set?
- `Subscription` errors: you have MSFT infra problems
    - Ensure you are enrolled and have `TM-GHAE` access
    - Is MSFT VPN connected?
- `sha-orchestrator` problems: force a new `--provision` step when rerunning `script/setup`
- Routing problems: it's DNS
    - MSFT and GitHub VPN address ranges overlap - both cannot be active on your machine at once!
- Seeing `Error response from daemon: Get https://ghcr.io/v2/: denied: denied` when trying to update a service SHA?
    - You need to log into the GitHub Container Registry. Use `docker login -u [username] -p $GITHUB_TOKEN ghcr.io`
    - If you've already logged in, you might be seeing this error because `docker login` is taking too long. Try again!
- When deploying, failing with a super vague error like `Deploy failed, the resource ghae in namespace default reported back with a failed status code. The resource is of type GitHubInstance.enterprise.engineering.github.com.`?
    - Check your pods (`kubectl get pods`). If one of them is crashing, you can `kubectl logs [pod-name] --follow` to investigate what occurred.
- What have I done? What am I doing?! What will I do?!?!!
    - **Hop into the `#ghae-friction` Slack channel for assistance (hint: try searching the channel history too!)**
