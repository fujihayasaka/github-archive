# bp-dev

The Build Pipelines Enterprise environment is one of several ways to interact with a development instance of our Enterprise products. A "bp-dev" instance is especially useful when you need to _iteratively apply updates_ to the local `enterprise2` or background services' codebases during development.

## Restrictions

The `bp-dev` environment has some limitations specific to Dependency Graph and Supply Chain services worth noting here:

* No organization Insights view, even with DG and related security products enabled
* Dependency Graph products and Github Connect:
  * DG products no longer require GH Connect to be _enabled_ in GHES/GHAE
  * Vulnerability Sync _does_ require GH Connect
* No package-to-repo mappings available in the Enterprise appliance:
  * Unlike vulnerabilities sync, this dataset is too large to export for Enterprise products
  * Calling back to dotcom for this metadata and caching upon request hasn't been implemented yet
  * Example: repository Insights (network views) won't be able to display links back to packages' source repositories

## Terminology

* **"build" environment**:
  * Hubot informs you when this environment is ready, after running `.bp-dev launch ...` chatops
  * Accessible via `ssh -A build@<BP_DEV_HOST>` from your local machine, via Dev VPN (see below)
  * Includes a full `enterprise2` checkout (`HEAD` of `master` branch, unless overridden in the `.bp-dev` chatop call (see below)
* **"admin" environment**:
  * This is the environment that our Enterprise product runs in
  * It includes [Nomad](https://www.nomadproject.io/)-managed containers for the Rails monolith, and all related services that ship with our Enterprise products
  * Accessible from your "build" env, via `./chroot-ssh.sh` (see below)

## bp-dev chatops

* **Create**: `.bp-dev launch [ghe | ghae] [--enable_ui] [--branch <ENTERPRISE2_BRANCH> | --sha <ENTERPRISE2_SHA]`
  * `--enable_ui` **skip this** for spin-up velocity, if you need to run `sudo update-reverse-proxy` downstream!
  * `--sha` and `--branch` options will override the [enterprise2](https://github.com/github/enterprise2) default branch that will manage your instance
  * When your instance is ready, Hubot will post a reply to your chatop:
    * **IMPORTANT!**: you _must_ be logged into the **GitHub DEV VPN** to access your `bp-dev` instance
    * Use the `ssh -a ...` incantation  to SSH into the "build" env on your `bp-dev` instance
    * `cd /workspace/enterprise2`
    * Optional: `git pull` (updates `enterprise2` checkout on the `bp-dev` if needed)

## bp-dev Supply Chain bootstrap sequence

The steps outlined below result in a running, `bp-dev`-based GHES instance with all Supply Chain security products enabled, including all supporting components:

* Fully enabled `ghe-admin` user (site admin with "Enterprise Settings" access)
* GH Connect ready to use, including bootstrapping dotcom Enterprise org if needed
* Self-hosted Actions runner storing logs w/minIO
* Dependency Graph, Dependabot Updates, Dependabot Alerts all enabled and working/usable
* Enterprise GitHub instance, and all support services (MySQL, Hydro, Aqueduct, etc.)

_Following all steps in order_ can prevent the need to rerun the most time-consuming bits of the dev inner loop (`sudo update-reverse-proxy`, `./chroot-configure.sh` etc.) any more than you need to.

1. Build, configure, and spin up the Enterprise instance on your node (from **"build" env**):

    ```bash
    # if needed
    cd /workspace/enterprise2

    # ignore errors if already stopped
    ./chroot-stop.sh

    ./chroot-build.sh
    ```

    ```bash
    # Start the container
    ./chroot-start.sh
    ```

1. Set up and enable Supply Chain services:

    From **"build" env**:
    * **IMPORTANT!** _**EITHER**_ set the vars below _**OR**_ enable the services **after** running the configure step below via the Enterprise Management Console security tab by navigating to `https://<BP_DEV_HOST>:8443/setup/settings#security`

    ```bash
    export ENABLE_DEPENDENCY_GRAPH=1
    export ENABLE_DEPENDABOT=1
    export ENABLE_ACTIONS=1 #also set by Dependabot but may decouple in future; set it yourself here too!
    export ENABLE_MINIO_ACTIONS_LOCAL=1 #replaces "Bootstrap Supply Chain services and Actions" step below
    ```

    * Run the configure script

      ```bash
      ./chroot-configure.sh
      ```

      * ^ if this fails on lock errors, run `./chroot-ssh.sh tail -f /data/user/common/ghe-config.log` and wait
      * rerun after `ghe-config.log` indicates previous (locked) config-apply run is completed
      * if the error still persists, you could delete the PID file and rerun

        ```bash
        ./chroot-ssh.sh

        rm  /var/run/ghe-config.pid # you may need to use sudo
        ```

        **WARNING!** This should only be used as last resort when all running processes have completed and PID file has hung around in error

    * **AFTER** successful configure run: sanity-check the blob storage is configured correctly:

        ```bash
        ./chroot-ssh.sh
        ghe-actions-check -s blob
        ```

1. Set up reverse proxy and Internet gateway (for Dependabot/GH Connect):

    From **"build" env**:

    ```bash
    sudo update-reverse-proxy
    ./chroot-add-gw.sh
    ```

1. Sanity-check: Supply chain services enabled:
    * Browse `https://<BP_DEV_HOST>:8443` (Enterprise management console)
    * Verify critical enabled functionality:
        * `Security` tab: Dependabot and Dependency Graph are enabled
        * `Actions` tab: Actions is enabled and configured, and the "Test" button validates storage is set up correctly
    * Browse `https://<BP_DEV_HOST>/login` and do so (user: `ghe-admin`, password: `passworD1`)
    * If redirected to `/join` page, do so (user: `ghe-admin`, password: `passworD1`, email: `admin@example.com`)
    * Once completed, `https://<BP_DEV_HOST>/users/ghe-admin` page should show `site admin: enabled` link at bottom of the page
1. Add GitHub root certificate to your `bp-dev` instance: [instructions here](#import-github-root-certificate-on-bp-dev)
1. Create a test organization (prep for GH Connect setup):
    * Do not follow prompts to convert `ghe-admin` account into an organization!
    * Use `ghe-admin` when creating test org (`+` dropdown from nav bar, "Create Organizations")
1. Set up and Enable GH Connect (for Dependabot):
    * Sanity-check: can `ghe-admin` user access Enterprise Settings?
        * Browse `https://<BP_DEV_HOST>/enterprises/github`
        * If 404 (or otherwise inaccessible) [follow these instructions](#enterprise-settings-access-for-ghe-admin)
    * Sanity-check: Do you need to set up your own (dotcom) Enterprise org?
        * Do this if you can't or don't want to use the (shared) [Avocado Corp.](https://github.com/enterprises/avocado-corp/)
        * Detailed instructions [here](./dependency_graph_in_ghes.md#setting-up-your-own-enterprise-org)
    * GH Connect enablement instructions [here](./dependency_graph_in_ghes.md#setting-up-gh-connect)
    * **IMPORTANT!** Once GH Connect is enabled, be sure to:
        * Browse or verify you're at `https://<BP_DEV_HOST>/enterprises/github/settings/dotcom_connection`
            * Dependabot section: set dropdown to `Enabled without Notifications`, and button to `Enabled`
            * Actions section: set Enabled
            * Press green button to apply updates as prompted
1. Set up Action Runner and associate with test repository (for Dependabot, or testing our DG/DS Actions!):
    * Browse to: `https://<BP_DEV_HOST>/<YOUR_TEST_ORG>/<YOUR_TEST_REPO>/settings/actions/runners`
    * Select (right side) Green button for `New Runner`
    * Choose **Linux** and **x64**
    * Copy and paste each relevant line of the displayed code snippet into a **"build"** (non-chroot!) session
    * When running the `config.sh` line, you will be prompted to select Actions self-hosted Runner options
    * **IMPORTANT!** Choose defaults, _except for the custom runner labels prompt:_ add a label named `dependabot`
    * Edit generated `run.sh` script to disable TLS checks and register GitHub root certificate obtained earlier:
        * `export NODE_EXTRA_CA_CERTS=/usr/local/share/ca-certificates/extra/github_root.crt`
        * `export CUSTOM_CA_PATH=/usr/local/share/ca-certificates/extra/github_root.crt`
    * Finally: `./run.sh` (**this blocks!**) to activate the runner and process Dependabot Updates jobs
    * Troubleshooting doc [here](https://github.com/github/dependabot-updates/blob/main/docs/development/working-on-ghes.md#using-your-bp-dev-instance)
1. Sync vulnerabilities:
    * UI method: Browse `https://<BP_DEV_HOST>/stafftools/vulnerabilities` and press **Sync Vulnerabilities Now** button
    * Detailed options (CLI and UI) are [here](#sync-vulnerabilities)
1. Create test repositor(ies):
    * Create them under your test org
    * Browse: `https://<BP_DEV_HOST>/<YOUR_TEST_ORG>/<YOUR_TEST_REPO>/settings/security_analysis`
        * Verify all Dependabot Alerts/Updates, Dependency Graph, and Advanced Security products are **Enabled**
        * Update (mash buttons) if not
    * Populate now or add files later according to your testing needs
    * Browse `https://<BP_DEV_HOST>/<YOUR_TEST_ORG>/<YOUR_TEST_REPO>/network/updates`
    * Press green button to create a `dependabot.yml` config file
    * **IMPORTANT!** fill in _at least one language ecosystem_ in order to commit the YAML file
    * Optional: create some manifest or other files for testing in the repo

#### Dev Inner Loop

While testing on a `bp-dev` instance, you may surface bugs in Nomad services (such as Dependency Graph!) that may prompt you to PR a fix on the repository of that service. Ideally, we want to test this bugfix before merging it, and without spinning up a new `bp-dev` from scratch by following the instructions [here](#update-bp-dev-service-verions).

* Once your bugfix PR is well tested, you'll want to update the production `enterprise2` SHA for that service:
  * Merge your bugfix PR on it's associated service repository
  * Chatops: `.ghe sha1-sync <BRANCH_NAME_OR_SHA> <SERVICE_NAME>` (generates an `enterprise2` PR)

#### Browser Access

Popular destinations to browse on your running Enterprise instance:

* **Stafftools**: `https://<BP_DEV_HOST>/stafftools`
  * Redetect Repo Manifests: `https://<BP_DEV_HOST>/stafftools/users/<YOUR_TEST_ORG>/dependency_graph/org`
  * Dependency Graph/Dependabot Repo Stafftools: `https://<BP_DEV_HOST>/stafftools/repositories/<YOUR_TEST_ORG>/<YOUR_TEST_REPO>/dependency_graph`
  * Dependabot Vulnerabilities Sync: `https://<BP_DEV_HOST>/stafftools/vulnerabilities`
* Org-level Security settings: `https://<BP_DEV_HOST>/organizations/<YOUR_TEST_ORG>/settings/security_analysis`
* Repo-level Security settings: `https://<BP_DEV_HOST>/<YOUR_TEST_ORG>/<YOUR_TEST_REPO>/settings/security_analysis`
* **Admin Settings**: `https://<BP_DEV_HOST>/settings`
* **Enterprise Settings**:  (this is where you can set up GH Connect!) `https://<BP_DEV_HOST>/enterprises/github/settings/dotcom_connection`
* **Enterprise Console**: (this is UI to enable DG/DA/DU services - favor CLI instead!) `https://<BP_DEV_HOST>:8443`
* **Action Runner Setup**: `https://<BP_DEV_HOST>/<YOUR_TEST_ORG>/<YOUR_TEST_REPO>/settings/actions/runners/new`

## HOWTOs

#### Access Bash shell on any Nomad container

* `./chroot-ssh.sh` (if you haven't already)
* Some Nomad jobs have quick-access scripts:
  * `github-env` for monolith session
  * `ghe-dependency-graph-api-env` for DG-API session
  * Many other GHE Nomad jobs have a similar script, check first!
* Alternate: manual version, works to access any Nomad allocation:
  * Use `nomad status` to surface available job allocations (running processes)
  * Use the process outlined below to access any of the listed allocations

Example: access shell session on `dependency-graph-api-service` Nomad allocation:

* `./chroot-ssh.sh` (if you haven't already)
* Access the `dependency-graph-api-service` container:
  * `source /usr/local/share/enterprise/ghe-nomad-lib`
  * `alloc_id=$(find_allocation "dependency-graph-api-service")`
  * `run_in_allocation "$alloc_id" "/bin/bash"`

#### Clear/Redetect Manifests

Dependency Graph Vulnerabilities sync (UI):

* Browse to `https://<BP_DEV_HOST>/stafftools/repositories/<YOUR_TEST_ORG>/<YOUR_TEST_REPO>/dependency_graph`
* Push `Clear dependencies` or `Redetect Manifests` button(s)

#### Sync vulnerabilities

There are multiple methods for triggering a vulnerabilities data sync from dotcom to your `bp-dev` instance.
**IMPORTANT!** GH Connect _must be set up and working_ before attempting to sync vulnerabilities!

Dependabot Vulnerabilities Sync (UI):

* Browse to `https://<BP_DEV_HOST>/stafftools/vulnerabilities`
* If 404, validate your GH Connect config has enabled Dependabot (dropdown, choose w/o notifications)
* Top of page, "Sync Vulnerabilities Now" button

Dependabot Vulnerabilities Sync (dotcom console):

```bash
# start "admin" env session if you haven't already
./chroot-ssh.sh

# load gh/gh Nomad container session
github-env

#dotcom Rails console
bin/rails c

VulnerabilitySyncWithDotcom.perform_later
```

Dependency Graph Vulnerabilities sync (console):

* Access the `dependency-graph-api-service` container [as documented here](#access-bash-shell-on-any-nomad-container)
* From bash shell on `dependency-graph-api-service` container:

  ```bash
  bundle exec rake sync_vulnerabilities
  ```

* From Rails console session on `dependency-graph-api-service` container:

  ```bash
  script/console
  ActiveRecord::Base.connected_to(role: :writing) { VulnerableVersionRange.sync }
  ```

#### Bootstrap Supply Chain services and Actions

* Based on instructions in [this doc](https://github.com/github/dependabot-updates/blob/main/docs/development/working-on-ghes.md#running-a-self-hosted-actions-runner-for-dependabot-updates)

```bash
# start "admin" env session if you haven't already
./chroot-ssh.sh

# set up MinIO bucket for Actions
ghe-minio-client mb minio/github-actions
ghe-config secrets.actions.storage.blob-provider s3
ghe-config secrets.actions.storage.s3.service-url "http://localhost:10004"
ghe-config secrets.actions.storage.s3.bucket-name github-actions
ghe-config secrets.actions.storage.s3.access-key-id $(ghe-config secrets.minio.accesskey)
ghe-config secrets.actions.storage.s3.access-secret $(ghe-config secrets.minio.secretkey)
ghe-config secrets.actions.storage.s3.force-path-style true

# return to "build" env
exit
```

_NOTE: if the above is run out-of-sequence, an additional `ghe-config-apply` and/or `./chroot-add-gw.sh` may be required_

#### Import GitHub root certificate on bp-dev

Based on [this documentation](https://github.com/github/dependabot-updates/blob/main/docs/development/working-on-ghes.md#using-your-bp-dev-instance).
Before setting up the Actions runner itself, you will need to add the current root certificate to your bp-dev instance so it can
validate secure requests to the GHE instance:

1. From your local machine, connect to a GitHub Ops-Shell (bastion) instance and grab a copy of the current root certificate

    ```bash
    ssh <OPS_SHELL_HOST>
    cat $(find /usr/local/share/ca-certificates -name 'cp1-iad-production-*-root.crt' | head -1); echo
    ```

1. On your bp-dev instance, add the certificate and apply changes

    ```bash
    # from "build" env:
    sudo mkdir -p /usr/local/share/ca-certificates/extra
    sudo vi /usr/local/share/ca-certificates/extra/github_root.crt
    # ... paste the contents of the certificate here and save the file ...
    sudo update-ca-certificates
    ```

#### Inspect Config files

These values can be updated with `ghe-config` as well as read/referenced in config updates.

* **From "admin" env**:
  * View all resolved configs:
    * `GHE_CONFIG=<PATH_TO_conf_FILE> ghe-config --list`
  * App and service configs `/data/user/common/github.conf`
  * Secrets `/data/user/common/secrets.conf`

#### Update bp-dev service verions

* **From "build" env**:

```bash
#ignore errors if already stopped
./chroot-stop.sh
```

* For each service in question:
  * Browse to the source repository for the service (default branch, or optionally a PR/branch)
  * Navigate to the service's **Actions Tab** and identify the action that publishes the  Enterprise Docker Image. Examples:
    * `github/github` Actions [GHES](https://github.com/github/github/actions/workflows/build_enterprise_containers.yaml) and [GHAE](https://github.com/github/github/actions/workflows/build_ghae_containers.yaml)
    * [dependency-graph-api Action](https://github.com/github/dependency-graph-api/actions/workflows/actions-cibuild.yml)
    * [dependabot-api Action](https://github.com/github/dependabot-api/actions/workflows/enterprise.yml)
  * **IMPORTANT!** to use an image from a non-default branch or PR, _manually trigger the Action on your branch_ to publish an Enterprise image
  * Capture the **_Image Tag_** from the latest Enterprise image-publish Action run's logs
  * Update the relevant config files using the update service script in a **"build" env**:

  ```bash
  # e.g ./script/update-service.rb github 05b5360c50650da684d9983c349f5b616af71ae9
  ./script/update-service.rb <SERVICE_NAME> <IMAGE TAG>
  ```

  * Sanity-check:
    * Try `git diff` in the `/workspace/enterprise2` directory
    * Review SHA updates in config files: [here](https://github.com/github/enterprise2/blob/master/configuration.sh) and [here](https://github.com/github/enterprise2/blob/master/docker-image-list-ghe)
  _NOTE: If running out of sequence: these changes will not take effect until a `./chroot-configure.sh` or `ghe-config-apply` runs_

* Repeat step 1 in the [bp-dev Supply Chain bootstrap sequence](#bp-dev-supply-chain-bootstrap-sequence) section

#### Enterprise Settings Access for ghe-admin

If you can't access Enteprise Settings (**NOT** to be confused with Enterprise Management Console or Stafftools!) as `ghe-admin` user:

```bash
# start "admin" env session
./chroot-ssh.sh

#start `github-unicorn` container session
github-env

#start Rails console on gh/gh
bin/rails c
```

Fix perms so `ghe-admin` user can properly view `Enterprise Settings`:

```ruby
# sanity-check: both flag checks should be "true" if this is a GHES bp-dev
GitHub.single_business_environment?
ga = User.find_by(login: "ghe-admin")
GitHub.global_business.owner?(ga)
```

```ruby
# if ^ is "false", UPGRADE "ghe-admin" user to business owner!
ga = User.find_by(login: "ghe-admin")
GitHub.global_business.add_owner(ga, actor: ga)
GitHub.global_business.owner?(ga)
```

* Relevant code snip [here](https://github.com/github/github/blob/master/packages/admin/app/models/business.rb#L672-L704)

#### Nomad

[Nomad](https://www.nomadproject.io/docs) is used to orchestrate containerized services running on your instance. Some useful commands:

* View all running services: `nomad status`
* View container logs for Nomad services:
  * `journalctl -t <SERVICE_NAME>` (add `-f` to tail interactively, `--no-pager` to avoid truncation/scrolling)
* Add a collaborator (from the "build" session, no chroot-ssh.sh): `add-collaborator <GITHUB_LOGIN>`

## Troubleshooting

### DNS FAIL

If you can't _browse_ to your `bp-dev` instance (no routes) but:

* `sudo update-reverse-proxy` has already been run successfully, or you started the `.bp-dev launch ghe` instance with `--enable_ui` set
* SSH and local routing checks are all fine (`scutil --dns` and `dig -x <YOUR_BP_HOST>` etc.)
* Dev VPN is up and working

Then **this one neat trick** can help reset your DNS (apparently the Ruby DNS stack goes around typical system opts that "still work" in this instance!):

```Ruby
# From your local machine (not bp-dev instance!) - thanks to @bensherman for protip!
irb(main):001:0> require "socket"
irb(main):002:0>  Addrinfo.getaddrinfo "<YOUR_BP_DEV_HOST>", nil
```

### `ghe-config-apply`

This is run from the **"admin" env** (chroot) and is the equivalent of `./chroot-configure.sh` (with NO ENV VARS FLAGS SET!) in the **"build" env**.
Remember to use `ghe-config --list` (defaults to `github.conf`, check `secrets.conf` also!) to ensure additional runs of `ghe-config-apply` won't _disable_ services/features enabled using `export ENABLE...` env vars + `./chroot-configure.sh` during earlier steps!

### Disable TLS certificate checking

* Can be used with a self-hosted Actions runner during dev testing (alternative to importing the GH root certificate from ops shell.)
* These are the vars to set:

  ```bash
  export GITHUB_ACTIONS_RUNNER_TLS_NO_VERIFY=1
  export NODE_TLS_REJECT_UNAUTHORIZED=0
  export GIT_SSL_NO_VERIFY=true
  ```

* **WARNING!** this approach was suggested as a workaround by [`#actions-support`](https://github.slack.com/archives/CH7FM9MFC) folks but is _unvalidated_ atm, use at your own risk!

### `./chroot-reset.sh`

Danger! this resets the chroot env to a clean state so you'll need to redo setup steps  1 - 3 [above](#bp-dev-supply-chain-bootstrap-sequence)

### Dependabot Updates

Sanity-check: DU service up and running?

* **your laptop (on dev VPN!):** `curl https://<instance name>.service.bpdev-us-east-1.github.net/\_dependabot/\_ping`
* ^ If this fails [original notes here](https://github.com/github/dependabot-updates/blob/main/docs/development/working-on-ghes.md#this-doesnt-work)
Sanity-check: trouble setting up/configuring services (Actions etc.)
* [Details here](https://github.com/github/dependabot-updates/blob/main/docs/development/working-on-ghes.md#getting-dependabot-api-running)

## Links/Docs

* <https://thehub.github.com/epd/engineering/products-and-services/ghes/development/>
* <https://thehub.github.com/epd/engineering/products-and-services/dotcom/github-connect/>
* <https://github.com/github/ghes/blob/main/docs/getting-started/using-single-tenant-ghe-developer-instances.md>
* <https://thehub.github.com/epd/engineering/products-and-services/ghes/utilizing-test-helpers/>
* <https://thehub.github.com/epd/engineering/products-and-services/ghes/feature-flags/>
* <https://github.com/github/dependabot-updates/blob/main/docs/development/working-on-ghes.md>
* <https://github.com/github/c2c-actions/blob/main/docs/ghes/README.md>
