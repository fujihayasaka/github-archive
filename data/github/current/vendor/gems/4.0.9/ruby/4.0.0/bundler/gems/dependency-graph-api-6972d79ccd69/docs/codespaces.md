# Dependency Graph in Codespaces

## Running dependency-graph-api by itself

1. [Create a new Codespace on dependency-graph-api](https://github.com/github/dependency-graph-api/codespaces)
2. Wait for setup to complete
3. Run `script/setup` for basic configuration, dependency install, and DB setup.  Wait for it to complete.
4. Run `script/server` to run the development server
5. The development server is available at `http://localhost:9596/`
6. Confirm all is well using `curl http://localhost:9596/_ping`.  It should return something like `{"status":"OK","time":1739810937}`

## Running dependency-graph-api with the monolith

### Using codespace-compose

1. Download and authenticate [with the `gh` CLI tool](https://cli.github.com/manual/) on your Mac
2. Install [the `gh-codespace-compose` extension](https://github.com/github/gh-codespace-compose)
3. Either clone the dependency-graph-api repo to your Mac, or just download the [codespace-compose.yml](../codespace-compose.yml) file to some directory.
4. Run `gh codespace-compose up code` to create the Codespaces and open VS Code.
   * **NOTE:** Codespace-compose uses SSH port forwarding through your local machine to create the network between the Codespaces. For this reason **you must keep it running in your terminal while are you are working.**
   * **NOTE:** In this configuration, `dependency-graph-api` uses the MySQL instance running in the `dotcom` Codespace. Tests will be much slower to run due to the network delay (`dg-api --[ssh tunnel]--> your machine --[ssh tunnel]--> dotcom --[ssh tunnel]--> your machine --[ssh tunnel]--> dg-api`).
5. Run `script/server` in the Dotcom Codespace that was created (the `DEPENDENCY_GRAPH_API_URL` environment variable should already be set!)
6. Run `script/server` on the dependency-graph-api Codespace
7. If you run into issues, verify the networking is still working in codespace-compose. You should see some messages like this:

     ```plain
   DEBU[0007] Setting up ports for github
   DEBU[0009] Forwarding port from github :18081 <- :53707
   DEBU[0009] Forwarding port to github :9596 -> :53708
   DEBU[0009] Forwarding port from github :9092 <- :53706
   DEBU[0009] Setting up ports for dependency-graph-api
   Forwarding ports: remote 80 <=> local 80
   DEBU[0011] Forwarding port to dependency-graph-api :9092 -> :53706
   DEBU[0011] Forwarding port to dependency-graph-api :18081 -> :53707
   DEBU[0011] Forwarding port from dependency-graph-api :9596 <- :53708
     ```

8. :tada: :dollar: :tada:

## Troubleshooting

### Authorization

If you are seeing 403s or token related errors when creating a
Codespace you will see a message like this one in the Codespaces creation log:

```plain
2022-11-29 14:56:54.892Z: #4 [internal] load metadata for ghcr.io/github/codespaces-base/codespaces-base:ce1a32a48008e5dfcc919c6065287626ae81c757
2022-11-29 14:56:54.975Z: #4 ERROR: failed to authorize: rpc error: code = Unknown desc = failed to fetch oauth token: unexpected status: 403 Forbidden
2022-11-29 14:56:54.975Z: ------
```

Check the latest [prebuild status](https://github.com/github/dependency-graph-api/settings/codespaces) for the repository.
If there are no errors, and you get an authorization error as above, there might not be a prebuild available for your region.

If that is the case, you can create a PAT for logging into ghcr.io on the Codespace with the following steps (also [on the public documentation](https://docs.github.com/en/codespaces/codespaces-reference/allowing-your-codespace-to-access-a-private-image-registry)):

1. Create a [new PAT](https://github.com/settings/tokens) with `read:packages` permission.
2. Copy the PAT value down
3. Enable SSO on the PAT
4. Create 3 [Codespaces Secrets](https://github.com/settings/codespaces) and give `github/dependency-graph-api` access to them:
   * `GH_CONTAINER_REGISTRY_SERVER`: `ghcr.io`
   * `GH_CONTAINER_REGISTRY_USER`: `[your_github_username]`
   * `GH_CONTAINER_REGISTRY_PASSWORD`: `[PAT from step #2]`

You should now be able to create a new Codespace on `github/dependency-graph-api`.


# Using codespace-compose with Actions

On a dotcom Codespace, the `actions-dev` plumbing can be activated and integrated with a running dotcom `github/github` server. In effect, this implements a limited-use, self-hosted Actions runner much like one can manually bootstrap in a `bp-dev` environment, that runs "inline" with other shared stores/services on the _dotcom_ container. Other than this change, our DG `codespace-compose` rig behaves exactly as is does for other end-to-end dev use.


### Bootstrap Dotcom Codespace + Actions

The following is a "speedrun" for bootstrapping the entire environment. Ordering matters here. This assumes you don't hit any transient problems as described above :) good luck!


**Bootstrapping all the codespaces things!**

1. _Local machine_:
    * Option 1: `gh codespace-compose -r github/dependency-graph-api up` (no local checkout needed)
    * Option 2:
        * Check out `github/dependency-graph-api` at `HEAD` of `master` branch (good for ad-hoc compose script hacking prior to launch)
        * `gh codespace-compose up`
    * **NOTE!** _This process blocks. Let it!_ It provides all _port forwarding_ between containers
1. _Local machine_: open 2 more terminal sessions:
    * `gh cs ssh` to `github/github` and run `script/server`
    * `gh cs ssh` to `github/dependency-snapshots-api` and run `script/bootstrap && script/server`
1. Once the the `github/github` server stable (logging slows down etc.):
    * `gh cs ssh` to `github/dependency-graph-api` then run `script/setup && script/server`
    * `gh cs ssh` to `github/github` and run `start-actions && script/actions-health-check`
       * _Note: the Actions health check is a good sanity check, but some errors are noise - ask in `#actions-inner-loop` for more info_
1. _Local machine_:
    * `gh cs ports` to see the port 80 URL for the `github/github` container
    * Browse to this URL and log in as `monalisa`; if trouble see the Troubleshooting section below
    * **DO NOT** attempt to run any Actions yet! (see below; use-case dependent!)


**Shutting down all the codespaces things!**

Assumption: everything is up and running smoothly already! This counts for anytime you want to wake up your Codespaces and keep working again at a later time, without messing up your environment:

1. `CTRL-C` DS-API server
1. `CTRL-C` DG-API server
1. _dotcom Codespaces CLI_: `stop-actions` - wait for this to complete
1. `CTRL-C` dotcom server
1. `CTRL-C` local `gh codespace-compose up` process to unblock

At this point you can let the system idle your Codespaces and they will wake up again once you restart `codespace-compose` and `ssh` into them. To permanently clean up/destroy the whole set of composed Codespaces:

* Option 1: `gh codespace-compose down`
* Option 2: `gh cs delete` for each Codespace spun up by compose, taken from `gh cs list`


**Setting up a test repo**

* The dotcom Codespace's self-hosted runner is only integrated with the dotcom Codespace's `github` org
* Test repos that will install/trigger Actions must:
    * **Be created in the `github` org** - `monalisa` is an admin, but self-hosted runner is only associated with `github`
    * **Be private repositories** - there is a security gap that prevents public repos integrating self-hosted runners!
    * **Be manually opted into Dependency Graph** in Repository Settings (b/c private repo)
* Manually-installed Actions YAML **must** be edited:
    * Must use `runs-on: self-hosted` rather than prod labels
    * All referenced Actions must be checked into the local _dotcom Codespace server_
    * See below for editing required  to _Actions you needed to install manually_!
* Validate Actions plumbing is bootstrapped and running:
    * All servers and related storage/services are up and running in all Codespaces, and logs look good
    * Port forwarding app is running (blocking on local machine) and logs look good
    * `start-actions` has completed and `script/actions-health-check` looks reasonable


**Bootstrapping Actions on your test repo and running a smoke test**

* Browser: visit the **Actions tab** on your test repo
* If the green activation button appears to initialize Actions on the repo, click it
* If you haven't installed any Actions on the repo yet, select the `Simple Workflow` and click `Configure`
* Check in the YAML (remember to **edit where needed** for `self-hosted` etc.!)
* Leverage `workflow_dispatch` directive in YAML: browse **Actions -> Run Workflow** to kick off a test run
* Observe that it completes without errors:
    * Initial runs can take a while to get through submission and into `Queued` status on the **Actions tab**
    * Keep an eye on Actions that stay in `Queued` or appear to hang for long periods; you can adjust the timeout if needed
    * Be wary of cancelling a workflow in "limbo" or making too many fast moves in dev env
    * See below on tailing subission (Launch/Kredz) and Runner/Worker (`actions-dev`) progress logs below
* For Dynamic Workflow testing: **The above smoke test, or some standard workflow run, _must_ be completed prior to initial DW submission**


**Utilizing Actions not pre-installed in the dotcom Codespace image**

* `gh cs ssh` to a CLI session on the `github/github` codespace
    * `cd /workspaces`
    * `git clone` each Action you'll require from it' public repository
    * Run: `ssh-keygen -t rsa -b 4096 -C "monalisa@github.com"` and select defaults at prompts
    * `echo /home/vscode/.ssh/id_rsa.pub` and copy to your clipboard
* Browse to your running `github/github` server:
    * Log in as `monalisa`
    * Browse to User Settings -> SSH and GPG Keys
    * Create a new SSH key scoped to `Authorization Key` and copy the `id_rsa.pub` contents as the value
    * Browse to the `actions` org
    * Create a _stub *PUBLIC* repository_ for each Action you plan to use in this env
* From `github/github` Codespace CLI session:
    * `cd` into the root of an Action you checked out
    * Browser: copy the **SSH clone URL** (HTTPS won't work!) for the stub repo you created earlier for this Action
    * `git remote add local <SSH_CLONE_URL>`
    * `git push local main`
    * **Rinse and repeat for each Action you checked out**
* Browse running `github/github` server:
    * Check that your `actions` org stub repos are now populated
    * **DON'T FORGET** to update your _references_ to these Actions in your _test repo workflow YAML!_:
        * Rename all Actions references to `actions` org and `main` revision!
        * Example: `advanced-security/setup-java@v3` for dev becomes `actions/setup-java@main`
    * Execute the Actions using the **Actions tab** on the repository, or by trigger (PR creation, push/merge etc.)


**Accessing dotcom APIs from the console**

The `GITHUB_TOKEN` included in the codespace won't cover you here, if you need to call APIs on behalf of `monalisa` user. In this case, create an _alternate PAT_ on the `monalisa` account (API or via server UI) and replace the `GITHUB_TOKEN` with it in your session. **WARNING:** copy the _original_ `GITHUB_TOKEN` into a file or otherwise cache it locally; you will need it again when you're not pretending to be `monalisa`.


### Troubleshooting

**I can't browse to the dotcom Codespace's server instance!**

* Try the full stop-and-restart dance described below under `brew services restart nginx`


**Port forwarding is broken and/or I'm seeing error logs in my running Codespace container services!**

The `gh codespace-compose up` command runs as a _blocking process on your local machine._ Check that:

* The `gh codespace-compose up` process is in fact running locally
* The `gh codespace-compose up` process is not logging port-forwarding errors
* `curl`ing services directly is working (on and off the Codespace hosting the service!)

NOTE! Stopping and restarting the port forwarding app will require restarts of various other services; see below.


**I'm seeing connectivity errors in the logs of 1 or more of my Codespace servers**

There are critical dependencies between services in our `codespace-compose` environment that must be respected if you need to stop and restart any of them! Namely:

* If you need to restart the DG-API service:
    * Have at it! This shouldn't trigger problems with other services
    * If you notice connectivity errors in the logs for particular services/stores, check on port-forwarding app
* If you need to restart DS-API service:
    * Have at it! no dependencies at the moment (just listens for HTTP/Twirp requests!)
    * Can lose connectivity with Spokes if port forwarding is broken; this needs addressing
    * **WARNING** as DS-API begins to depend on other services/stores (Hydro events etc.) _this will change!_
* If you need to stop and restart the dotcom server:
    * Stop the _DG-API server_ and then the _dotcom server_
    * Start the _dotcom_ server; wait for the log stream to idle
    * Start the _DG-API_ server
* If you need to stop and restart the `gh codespace-compose up` process handling port forwarding locally:
    * **Why?**
        * Seeing port forwarding error logs from the local compose process?
        * Seeing connectivity errors between services across the Codespaces' server logs?
    * Stop the _DG-API server_ and then the _dotcom server_
    * Stop and restart the local `gh codespace-compose up` process; wait for it to fully bootstrap then idle
    * Start the _dotcom_ server; wait for the log stream to idle
    * Start the _DG-API_ server
* If you need to `brew services restart nginx` on your local machine:
    * **Why?**: observing 5xx Nginx errors when you browse the running dotcom server
    * Sanity check: are you using the right port 80 URL found in `gh cs ports` for the `github/github` Codespace?
    * Stop the _DG-API server_, then _dotcom server_, then the _local `codespaces-compose up` process_
    * Start them all back up in the _reverse order_; wait for **each** to idle/stabilize before proceeding, unless you love pain
* If you need to restart `actions-dev` services:
    * **Why?**:
        * Expected Actions are not being enqueued when triggered (directly or by user activity)
        * Triggered Actions are hanging in `Queued` status without launching; eventually timing/erroring out
    * Dotcom Codespace `script/server` **must be bootstrapped, up, and idle** whenever Actions services are spinning up!
    * Doesn't require cycling any other services (normally)
    * `stop-actions && sleep 3 && start-actions`; more severe versions of this listed below :)


**Actions runs are not enqueued, or are hanging indefinitely in `Queued` state**

Triaging Actions fails can be tricky. Actions dev env is composed of many smaller components in the dotcom Codespace:

* Locally running OS-managed services in the container: `sudo service --status-all`, `sudo service <SERVICE_NAME> [stop|start|status]`
* Services run as part of the [dotcom codespace Overmind rig](https://github.com/github/github/blob/master/Procfile):
    * Check the [startup scripts referenced there](https://github.com/github/github/tree/master/script) for hints at lifecycle, where logs go etc.
* A minikube environment running in the _dotcom Codespace Docker_ (initialized by `start-actions`; try `k9s` to view)
* Other "standalone" Docker containers in the _dotcom Codespace Docker_

All of the below assumes:

* At _dotcom Codespaces CLI_
* Dotcom `script/server` is running smoothly, along with related Overmind processes and Docker
* `actions-dev` fully up and running and `start-actions` completed successfully (at some point earlier!)
* `script/actions-health-check` looking reasonable; [caveats here](https://github.com/github/c2c-actions/blob/main/docs/innerloop-debugging.md#four-nines) - `run-service` and some other transitional serices can appear broken but won't matter

Steps to Triage (greatest hits taken from [this master debugging doc](https://github.com/github/c2c-actions/blob/main/docs/innerloop-debugging.md)):

* Add verbose process logging to your test repo:
    * Browse `Repo Settings -> Secrets -> Actions`
    * Create 2 new Secrets:
        * Key: `ACTIONS_STEP_DEBUG`, Value: `true`
        * Key: `ACTIONS_RUNNER_DEBUG`, Value: `true`
* All Actions plumbing code and logs live in the _dotcom Codespace_ under `/workspaces/actions`:
    * `tail -f /workspaces/actions/launch/output.log` to see job submissions and submit-stage fail logs (auth, YAML validation etc.)
    * `tail -f /workspaces/actions/runner/_layout/_diag/*.log` to view Runner and Worker fail logs for successful submissions
        * ^ WARNING! these log files split often; make sure if you filter that you tail the latest
* The `minikube` instance in `Docker` - use `k9s` or [Skyrise console](https://github.com/github/c2c-actions/blob/main/docs/innerloop-debugging.md#actions-dotnet) to introspect on `actions-dev` internals


Steps to Remediate:

Easy mode...harmless, repeatable, might even help:

1. `stop-actions && sleep 3 && start-actions && script/actions-health-check`
1. `script/setup-codespaces-actions` in _dotcom Codespaces CLI session_, from checkout root
1. Use `k9s` from _dotcom Codespace CLI_
    * `0`, `l` to [review failed processes and their namespaces](https://github.com/github/c2c-actions/blob/main/docs/innerloop-debugging.md#actions-service-not-running) in `minikube` env
1. Consult debug doc and/or as `#actions-inner-loop` folks for [help](https://github.com/github/c2c-actions/blob/main/docs/innerloop-debugging.md#where-to-ask-for-help)

Hold onto your butts mode (usually ends badly):

1. Set up [Skyrise CLI](https://github.com/github/c2c-actions/blob/main/docs/actions-development.md#building) on dotcom Codespace and [start a session](https://github.com/github/c2c-actions/blob/main/docs/innerloop-debugging.md#actions-dotnet)
1. Run [kredz](https://github.com/github/c2c-actions/blob/main/docs/innerloop-debugging.md#launch) or [launch](https://github.com/github/c2c-actions/blob/main/docs/innerloop-debugging.md#launch) directly
    * Check `script/server`, `sudo service --status-all` etc. first
    * Services under `/workspaces/actions/<SERVICE>` like these often log to `output.log` or `_layout/_diag` in their subdir
1. Hard replace `actions-dev` components with `deploy` cmds
    * This rarely works; consider reaching out for help or starting over from scratch!
    * Requires resettings the dotcom tenant mappings and re-associating Runner setup; [details here](https://github.com/github/c2c-actions/blob/main/docs/innerloop-debugging.md#how-to-restore-runner-registration-after-deploy)
1. Misc. [troubleshooting tips](https://github.com/github/c2c-actions/blob/main/docs/innerloop-debugging.md#miscellaneous-troubleshooting)


**What if a cross-service shared store is unresponsive across Codespace instances?**

Let's use Spokes as an example. It runs as part of the _dotcom_ `script/server` process managed by Overmind.

Here's a `curl` incanctation that should work in dev to check Spokes is connected and working:
```
> curl -vvv -L 'http://127.0.0.1:28081/twirp/spokes.Spokes/Status' -d '{"repository": { "type": 1, "repositoryId": 1, "networkId": 1 } }' -H "Content-Type: application/json"

# Should respond with 200 OK and:
{"available": true}
```

Steps to Triage:

1. Is the dotcom Codespace's `script/server` up and running? No logged Spokes errors in the Overmind log mux?
1. Do you see Spokes-related errors logged in the DS-API or DG-API Codespaces' server logs?
1. Is the port forwarding app (blocking locally with `gh codespace-compose up`) throwing errors? (this is often this is the culprit and the fix!)
1. Can you run a test call (posted above) to dev Spokes from the _dotcom Codespace_?
1. Can you run the same test call on the _DG-API_ and _DS-API_ Codespaces? (this is often the problem resetting port forwarding can fix!)

Steps to Remediate:

1. Using the order-dependent restart cycles described above, reset your local `gh codespace-compose up` process and all dependent processes
1. Try the test `curl` from the dotcom (remember `script/server` must be running there!) and then all the other Compose instances
