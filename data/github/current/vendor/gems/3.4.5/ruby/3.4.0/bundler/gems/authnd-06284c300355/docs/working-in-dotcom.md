# Working in dotcom

dotcom refers to the github/github repo, the contents of which are typically seen in the deployed github.com instance.

In order to properly develop authnd, you will likely need to work alongside a local dotcom environment.
Since we are primarily targeting dotcom scenarios for authnd right now, the dev loop will often require close iteration between authnd and github/github.
This doc describes patterns and tips for doing that.

## A note about Enterprise

Remember that github/github code is used for both dotcom and enterprise.
We are not currently targeting enterprise, so any code added to dotcom should be disabled on enterprise. You can do this by using a feature flag that's globally disabled. Refer to the [Enterprise Development](https://thehub.github.com/engineering/development-and-ops/enterprise-development/#feature-flags) docs in The Hub for more information on Feature Flag related to enterprise development.

## Connecting to authnd from dotcom

By default, authnd connects to the `github_development` database on your local mysql.
If you've launched dotcom locally, you're all set.
Similarly, our authnd integration with dotcom is automatically configured to point to a local authnd instance.

Currently, we do **not** launch authnd as part of the `Procfile` in dotcom.
This means that by default, any code paths that use authnd will fail to connect unless authnd is running locally.
These code paths should always be behind [science blocks](https://github.com/github/scientist).

The dotcom monolith knows how to connect to authnd via the `GitHub.authnd_service_url` setting.
In the development environment, this points to `http://localhost:8000`, which is where authnd launches by default.
You can configure this in dotcom via the `AUTHND_SERVICE_URL` environment variable if you need to point it to a non-local instance of authnd.

Local development instances of authnd use a hard-coded hmac secret, and dotcom has that setting in the `GitHub.authnd_service_hmac_key` setting.

All of this generally means that if you launch dotcom (or parts of dotcom) locally, and launch authnd locally, they talk to each other by default.

To launch both services side-by-side using codespaces, you'll first want to get your dotcom development service running with `CODESPACES_DEFAULT_CUSTOM_PORT=1 script/server --debug`, then from a new shell in the same dotcom codespace run `script/setup-codespaces-authnd -d <development_branch_name>`. From there you can run `cd /workspaces/authnd ; script/server --no-replication --mysql-port 3306`, or open the workspace `cd /workspaces/authnd ; code .` and launch the service using the vscode `run and debug` (shift cmd D) option to debug authnd requests.

When you connect to the codespace mysql instance you should initially only see the dotcom databases. The authnd setup script run by `script/setup-codespaces-authnd` handles the migrations for the `github_development_authnd` database, which you should be able to connect and seed data into for testing purposes after you've setup the authnd workspace.

## How the Ruby client gets to dotcom

The ruby client for authnd is found in the `ruby` directory.
See [the ruby client README](../ruby/README.md) for more info.

## How the server gets to dotcom

It doesn't (for now).

## Local gitauth development loop

A local gitauth development loop between dotcom and authnd requires a few running processes

### Launch authnd

In one terminal, window/tmux, session/etc. go to `github/authnd` and run `make && script/server` to launch the server.
As you make changes to the service, re-run `make` and launch again.

### Launch dotcom

Refer to the [Local development environment](https://thehub.github.com/engineering/development-and-ops/development-environment/#local-development-environment) docs in The Hub for steps on running dotcom locally if you have not run it locally before.

Launch `script/server` as usual and it will connect to your locally running authnd instance.

### Launch dotcoms gitauth only

If you're just working on gitauth, you can just launch (in separate terminals) `script/babeld-server` and `script/gitauth-server`.
Using `binding.pry` will break in to your `script/gitauth-server` window.
As you make changes in gitauth, re-launch `script/gitauth-server`.
It's not necessary to re-launch babeld, but since it cached gitauth responses for up to 30 seconds, you may find it useful to do so.

If you need to change the authnd ruby client, stop `script/gitauth-server` and follow the steps in [the ruby client README](../ruby/README.md) to update the gem and vendor it in to `github/github`.
Then re-launch `script/gitauth-server` (again, babeld should not need to be restarted).

## Feature Flags and Experiments

Authnd is behind a global feature flag `authnd_experiment`.
If you haven't already, you'll have to enable the feature flag by running the following command:

```shell
$ bin/toggle-feature-flag enable authnd_experiment
```

Even with the feature flag enabled, the authnd experiment will not run.
Since we're behind [scientist](https://github.com/github/scientist) and the default database is configured with no experiments enabled.
To enable the experiment, open the rails console (`script/console` in github/github) and run the following command:

```ruby
Experiment["authnd.gitauth.verify_public_key"].adjust 50
```

Where `authnd.gitauth.verify_public_key` is the name of an experiment and `50` is any integer between `0` and `100` (inclusive) indicating the percentage of requests that should enable the experimental code path.

You can check the current percentage of a experiment by running the following command:

```ruby
Experiment.percentage name
```

Note that there is some caching in place, using memcached.
To clear the cache for a particular experiment, run:

```ruby
GitHub.cache.delete(Experiment.key("authnd.gitauth.verify_public_key"))
```

## Wrap changes in science

We use [science](https://githubber.com/article/technology/dotcom/science) to make sure authnd is producing the correct results and to protect users against bugs in authnd.
Always wrap any changes you make in an `Authnd::Experiment`, our custom experiment protocol. For example:

```ruby
# Authnd experiments should always start 'authnd.'
e = Authnd::Experiment::new "authnd.my_cool_experiment"

e.use { the_original_codepath }
e.try { the_authnd_enlightened_codepath }

# Use any other scientist features, like '.ignore`, etc. here

# Run the actual experiment. This returns only the result from the 'use' block.
e.run
```

**DO NOT** use `science` blocks, as they will use the default `GitHub::Experiment` class and you won't get our useful features.

The `Authnd::Experiment` class adds a few extra features on top of the default science experiment:

* A global `100ms` timeout that ensures that the experimental code path **never** goes above that duration. Configurable via `GitHub.authnd_service_experiment_timeout`
* A global "killswitch" via the `authnd_experiments` feature flag. If this feature flag is disabled, all experiments will be globally disabled.

Before deploying, you'll need to provision the science experiment in devtools using the name specified in the code.
