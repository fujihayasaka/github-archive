# How We Develop

This document provides the fundamentals on how to develop authnd and work within the github/authnd repo

## Setting up your environment

1. Clone the repo
2. Run `script/bootstrap`
3. Run `script/setup`

## Building

Build `authnd` by running `make`.

## Testing

Run unit tests with `make test`, this runs all tests that **do not** specify the `db` build tag.

Run integration tests with `make test-ci`, this includes tests that include the `db` build tag (make sure you've run `script/setup` at least once).

CI will run the same tests against a MySQL container when you open a Pull Request.

Some tests collect log output in the event of a failure, but this is off by default.
Set the `AUTHND_TEST_LOGGING` environment variable to `1` to enable it.
Test logs will be part of the output for that test *if the test fails*.

To debug tests, you can enable `Code Lens` which is built into vscode. With this you will see a `debug test` option above a test section. Clicking this will launch the debug console and run the test.

## Linting

Keep the code squeaky clean by running `make lint` to run linters and formatting checks.

## Vendoring dependencies

Any time a dependency is added, the version is being bumped (e.g. Dependabot), or a dependency is being removed, you need to update the vendor directories.

To do so, run the following commands and check in the changes:

```bash
  go mod vendor
  cd client; go mod vendor
```

## Running authnd

It's highly recommended that you launch github/github before launching authnd, since we depend on replicating data from dotcom. If this is your first time pulling github/github, try `git clone --depth 1` to pull a shallow copy as the history for github/github is _massive_.
The first time you run authnd, we recommend running `script/server --resync` to copy over data from your local dotcom instance.
This script will launch the replication and the main API server.
For future launches, you can use `script/server`, and the replication should catch up with things that changed since your last launch.

## Making requests

### Using the command line client

There is a command line client available for most ad-hoc testing scenarios.
See [Authnd Command Line Client](authnd-cli-client.md) for more information.

### Using curl

You can make requests to your local `authnd` instance using `curl`.
Twirp services like `authnd` support both JSON and Protobuf messages. For example:

**NOTE:** You'll need to generate an HMAC in order to make requests to your local copy of `authnd`.
See [HMAC Authentication](hmac-authentication.md) for more info.

```(bash)
$ curl --request "POST" --verbose \
       --location "http://127.0.0.1:8000/twirp/github.authentication.v0.Authenticator/Authenticate" \
       --header "Content-Type:application/json" \
       --header "Request-HMAC:$(./script/gen-hmac)" \
       --data '{
         "source_ip": "0.0.0.0",
         "credentials": {
           "ssh_public_key_fingerprint": {
             "sha256_fingerprint": {
               "fingerprint": "[base64 fingerprint]"
             }
           }
         }
       }'
```

## Testing chatops locally

`./bin/authnd-client chatop -- ping`

## Changed proto files?

If you've changed proto files, run `make protoc` to re-run the protoc compiler and update the generated Go and Ruby code.

### Notify proto

The proto definition for the notifyd messages also live in the [hydro-schemas](https://github.com/github/hydro-schemas/blob/main/proto/hydro/schemas/notifyd/v0/notify.proto) repository. This schema is used to publish messages which trigger a mobile push notification. To regenerate the Golang code under authnd, run this command from the `hydro-schemas` repository:

```bash
script/generate --go-out <path_to_this_repo>/internal/common/publisher proto/hydro/schemas/notifyd -p github.com/github/authnd/internal/common/publisher
```

### Mint PATv2 Event proto

The proto lives in the [hydro-schemas](https://github.com/github/hydro-schemas/blob/main/proto/hydro/schemas/authnd/mint/v0/pat_v2_event.proto) repository, and is used to publish PATv2 events. To regenerate the Golang code under authnd, clone the `hydro-schemas` repository in the same file system as authnd, then run this command from the `hydro-schemas` repository:

```bash
script/generate --go-out <path_to_authnd_repo>/internal/common/publisher proto/hydro/schemas/authnd/v0/programmatic_access_event.proto -p github.com/github/authnd/internal/common/publisher
```

You may have to change the generated file's package from `v0` to `hydro_schemas_authnd_v0` afterwards

## Access vault-bastion / Change secrets

The vault-bastion is where secrets, like connection keys and DB passwords, are stored. We can access it via the terminal and view and update the values.

* Make sure you have [entitlements](https://thehub.github.com/engineering/security/production-shell-access/troubleshooting/#cant-get-logged-in-to-the-bastion-at-all) for the shell access.
* Then run the following commands:

```(bash)
ssh vault-bastion.githubapp.com //enter the shell
. vault-login // login to the vault
vault-secret --application authnd // view secrets
vault-secret --application authnd -e production --key <keyname> --prompt //update the secret
```

**WARNING** Use caution when handling secrets! In particular:

1. Do not store them anywhere other that vault, or if **absolutely necessary* your local machine (and delete them when you are finished)
2. Never paste secret values in to command lines (for example `vault-secret --application authnd -e production --key <keyname> --value <secret>`). Instead, use `--prompt` and paste the secret at the prompt.
   * Commands entered in to your shell are stored in a history file.
   * If you accidentally put a secret in a command line, locate the history file (for bash, `~/.bash_history` and for zsh, `~/.zsh_history`).
   * Either delete the file entirely (clearing all history) or edit the file and remove the lines with the secret. Then restart your shell.

## Working with the Ruby Client

If you want to test out the ruby client locally, you can run `script/ruby-console` to launch the IRB console with the `authnd-client` gem loaded.

## Sending a PR

* Send your PR. A request to review from `@github/authentication` will be made.
* Get approval from at least one reviewer in that team and you're good to merge!
* Ask for help in `#authentication` if you need it!

## Merging your PR

In general, we follow the [`dotcom` deployment workflow](https://githubber.com/article/technology/dotcom/deploy/deployment#deployment-workflow),
which is that `main` always represent code that can be deployed to production safely.
That means we **deploy to production before merging**, in general.
If your change is limited to only client code, or documentation, you can skip the deployment and Hubot will auto-deploy after the merge.
If you are at all unsure what to do, it's better to deploy your PR.
That way, if something goes wrong, you can easily rollback.

So when your PR is ready to go, hop into the `#authnd-ops` slack channel and deploy your PR:

```(bash)
.deploy https://github.com/github/authnd/pull/<nr> to prod
```

If deployment succeeds, **merge your PR** and you are good to go. We always use the "Merge" option, *not* squash or rebase. If deployment **doesn't** succeed, to rollback by deploying the current `main` to prod:

```(bash)
.deploy authnd/main to prod
```

## Migrate the test databases

* Run `script/db-migrate test` for the test database
* Run `script/db-migrate test-ci` for the ci-test database

## Migrate the authnd_production cluster databases

1. To create a new table or to update an existing table: make the change in schemas/authnd
2. Create a PR with this change. This will trigger the skeefree CI build step to comment a diff with the change.
3. Confirm that the diff is correct then add the `migration:for:review` tag in the PR
4. You will need to wait for someone in the authentication-reviewers team to approve the PR before the rest of the process runs automatically.
5. The database-infrastructure team will review it as part of this process. The migration does not run immediately and can take days to run. Check with the database team if you are blocked.
6. Once hubot comments on the PR with the `complete` migration status, then you can merge the PR.
7. Create a new PR for the authnd_production migration
8. To create a new table or to update an existing table: make the change in schemas/authnd
9. repeat steps 3-6.

[This](https://github.com/github/authnd/pull/503) is an example of what the migration PR comments should look like.

You can read more about the skeefree migration process [here](https://github.com/github/skeefree/tree/master/docs)
