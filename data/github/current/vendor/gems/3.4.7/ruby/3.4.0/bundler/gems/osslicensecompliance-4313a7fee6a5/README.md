# OSS License Compliance

Backend for our License Compliance product.
Customers can create an open source policy at Enterprise, Organization and Repo level and
this service ensures that the licenses of their dependencies fulfill those policies.

See this [initiative](https://github.com/github/artifact-lifecycle/issues/98)
Phase 1 was completed before putting project on hold.

## Contact Us

- Team: `@github/artifact-lifecycle`
- Team Slack: `#dependency-graph`
- Team Slack Ops: `#dg-ops`
- Or you can [create an issue](https://github.com/github/osslicensecompliance/issues/new)


## Deployments

OSS License Compliance uses **Merge Queue** for automated deployments. Production deployments require pipeline completion, while staging can still be deployed manually.

### Staging

[OSS License Compliance Staging](https://devportal.githubapp.com/devportal/apps/osslicensecompliance)

**Manual deployment**: To deploy manually in Slack #dg-ops `.deploy osslicensecompliance to staging`

**Merge Queue**: Staging is also deployed automatically as part of the merge queue pipeline before production.

Twirp endpoint: `https://osslicensecompliance-twirp-staging.service.iad.github.net`

Staging instance is using a development database cluster. See mysql docs [here](docs/mysql.md)

### Production

[OSS License Compliance Production](https://devportal.githubapp.com/devportal/apps/osslicensecompliance)

**Deployment**: Production deployments are **only** available through the **Merge Queue** pipeline. Manual deployments to production are not permitted.

**Merge Queue Process**:

1. Create a pull request with your changes
2. Add PR to merge queue (use "Merge when ready" button or `.qmtd <PR>` (queue merge to deploy) in #dg-ops)
3. Pipeline automatically deploys to staging → production
4. PR auto-merges upon successful pipeline completion

Twirp endpoint: `https://osslicensecompliance-twirp-production.service.iad.github.net`

**Pipeline Monitoring**: Track pipeline progress at [Heaven Pipelines](https://devportal.githubapp.com/devportal/apps/osslicensecompliance?tab=deploysAndPipelines)

## Database access

See [docs/mysql.md](docs/mysql.md).

## Local setup

### Twirp API Null Mode

The service can be started in NULL mode.
This creates an in memory storage buckets for policy storage
Graph API responses

To start Null Service
```
make null-twirp-api
```

Server will run on `localhost:8080`

The responses for DG API can be found in the json files in `./null_seeds`.
Adjust these files as necessary.

### Local "real" mode

To run the service locally with a Mysql database and connected to DG API.

- Source .env.example env vars
- `docker compose up` to run azure storage
- Obtain a DG HMAC from slack Hubot with `.dg hmac` (Expires in 10 minutes`

Run the twirp server with:
```
DEPENDENCY_GRAPH_HMAC_KEY=<key> go run cmd/twirp/main.go
```

Server will run on `localhost:8080`

Need to be on the developer VPN

## Protobuf Generation

Proto files are in proto/oss_license_compliance/v0/

Use the `protobuf-gen` script (in a Codespace because the containers used are amd64 Linux) to generate the twirp files.

```
./script/protobuf-gen
```

If this is a new version, you can set the version when running `protobuf-gen`.  The default version is the current version.

```
./script/protobuf-gen 1.0.0
```

This generation process uses `Dockerfile-gen` to load the tools in an image that is used to generate:
* Go twirp files in `pkg/proto/v0`
* ruby twirp files in `ruby/lib`
* proto documentation in `proto/README.md`

## Twirp Test

There is a twirp test cmd at `cmd/twirp-test`
Currently supports commands
- `create_org` creates an organization policy using hardcoded values
- `get_org <id>` retrieves an organization policy


To use need to set `TWIRP_URL`

To test twirp server locally run `make null-twirp-api` to build and run the service on 8080

```
TWIRP_URL=http://localhost:8080 go run cmd/twirp-test/main.go create_org_policy
TWIRP_URL=http://localhost:8080 go run cmd/twirp-test/main.go get_org_policy 100
```

Staging (must be on dev vpn) 

Ensure HMAC header is set in env 
            
```bash
HMAC_SECRET=<hmac-secret> TWIRP_URL=https://osslicensecompliance-twirp-staging.service.iad.github.net go run cmd/twirp-test/main.go create_org_policy
```

Production (must be on dev vpn) and must provide a HMAC secret.

Ensure HMAC header is set in env. Use one of TWIRP_HMAC_KEYS in vault.
            
```bash
HMAC_SECRET=<hmac-secret> TWIRP_URL=https://osslicensecompliance-twirp-production.service.iad.github.net go run cmd/twirp-test/main.go get_org_policy 1

```

## Chatops Sample

This has not been configured with application, below is from service generator.

The sample chatops leverages the [`github/go-chatops`](https://github.com/github/go-chatops) library and requires the normal [`github/hubot-classic` setup](https://thehub.github.com/engineering/products-and-services/internal/chatops/) for RPC services. We recommend developers follow the Hubot guides and then use this sample for setting up their first chatop. Most of this implementation exist in `internal/chatops` folder.

We also provide some kubernetes configuration [to host your app on **Moda**](https://thehub.github.com/engineering/products-and-services/internal/moda/#what-is-moda). This configuration can be found in the `config/kubernetes/default` folder. Look for the files named `*chatops.yaml` in this project under the `./config` folder.

The configuration in the configmap should be setup as follows:

- `CHATOPS_AUTH_PUBLIC_KEY` : This is defined as the public key that is managed by [#friends-of-hubot team](https://thehub.github.com/engineering/products-and-services/internal/chatops/#production). We also provide some commented keys that match the values from [`github/hubot-classic` folder for development](https://github.com/github/hubot-classic/tree/main/test)
- `CHATOPS_AUTH_BASE_URL` : Defines the registered url that will be used in [hubot production config](https://github.com/github/hubot-classic/pull/4281/files#diff-1863bb96cade0032f625c68783840cb602a412b082bbbd6e83a489319e425fd5R2542) when you register the bot. We also provide an example setting that can be used for development testing. It's important that for production this is the full url for the service as provided by Moda because it's used in the `github/go-chatops` and hubot registration signature that is validated with the private/public key pairs for authorization. This URL will not be used by the RPC client to make http/https request.
- `CHATOPS_HTTP_ADDR` : Defines the port that the service is configured to listen on in deployments config for the `containerPort` setting and helps the service startup on that port.
- `CHATOPS_HEALTH_HTTP_ADDR` : This example implemnts a second http/https listener to provide a `/_ping` interface that can be used for kubernetes `readinessProbe` and `livenessProbe` testing. It provides the port for the service to bind to at startup. We don't make this portion of the service routable so it's not defined in the kubernetes services configuration.

Note that the design for these services relies on a single `./Dockerfile` located in the root of this project, which will have it's `command` changed at POD deployment time by kubernetes, so that the `cmd/chatops` code is used as a binary to startup our Chatops RPC service.

Building the binaries can be performed with the `make chatops` or `make build` targets.

The best way to get started with testing your service is to create a client. Our client testing code is located in the `cmd/chatops-test` folder for this project.
There are 2 sample commands `ping` and `hmac` included in go-sample-service. You can use these steps to test this locally:

1. Run `export CHATOPS_AUTH_PUBLIC_KEY=<public_key>` and set the key to HubotTestPublicKey from [go-chatops/certs.go](https://github.com/github/go-chatops/blob/ce8e08a9bdf07bc06b77cd59ca564dcf092c9277/certs.go#L12)
2. Start the chatops service by running `go run cmd/chatops/main.go`.
3. You can use `cmd/chatops-test/main.go` to test both commands.

If you are looking for a guide on fully running hubot and the rpc server locally for testing, we also provide a [hacking guide here](/docs/CHATOPS_HACKING.md).

## Testing in Monolith codespace

Prerequisites:
* There must be a branch in this repo with the changes you are testing.
* Spin up a codespace for the Monolith

_NOTE: The monolith triggers `script/bootstrap` in several situations.  It can block some of the recommended commands in this section until it completes.  You can check if it is running with `ps -aux | grep bootstrap`.  There will be a bunch of lines with `bootstrap-fork`.  Those are not relevant.  Look for lines that are consistent with this example._

```
vscode     11476  0.0  0.0   8900  3584 pts/2    S+   05:35   0:00 /bin/bash script/bootstrap
vscode     11611 11.5  0.0 636604 54256 pts/2    Dl+  05:35   0:02 ruby script/bootstrap.rb
vscode     11612  0.0  0.0   7312  1920 pts/2    S+   05:35   0:00 tee -a /tmp/github-bootstrap.log
```

_These will close one at a time as the script runs.  The script takes several minutes to complete.  If the script gets stuck, I found it helpful to restart the codespace._

### Add gem to Monolith

In Monolith's Gemfile have 2 options.

```
# using commit in ref
gem "osslicensecompliance-client", github: "github/osslicensecompliance", ref: "<commit_sha>"

# Using branch
gem "osslicensecompliance-client", github: "github/osslicensecompliance", ref: "my-proto-pr-branch"
```

After adding, run `bundle install`.  This will add the gem to `vendor/cache/gems/osslicensecompliance-client`.

### Test that Monolith picked up the gem

In a terminal in the Monolith codespace, check that it can find the gem's main entry point file.

```
$ bundle exec irb
irb > require 'osslicensecompliance-client'
=> true
irb > OSSLicenseCompliance::VERSION
=> "0.1.2"
```

Confirm that the VERSION returned is the one expected.  This will confirm that the gem is loaded and is at the expected version.  If there was a change without a version change, this will not confirm the code updated as expected.  If testing, you can make a change in osslicensecompliance and regenerate the gem with a distinctive version (e.g. `./script/protobuf-gen 0.1.2--elr`).

#### Troubleshooting

A couple of things to check:

* The monolith is looking for the gem in the location specified by `s.require_paths` in [osslicensecompliance.gemspec](https://github.com/github/osslicensecompliance/blob/main/osslicensecompliance-client.gemspec).
* Make sure that `s.require_paths` is correctly set to the full path where the gem's entry file lives.
* Make sure the entry file's name exactly matches the gem name specified in `s.name` in the gemspec file (_adding the .rb extension)_.

### Rebuild sorbet RBI files

#### Rebuild sorbet/rbi/gems

In a terminal in the Monolith codespace, run tapioca to rebuild the sorbet generated files.

```
./bin/tapioca gem osslicensecompliance-client
```

This generates module and class definitions with default methods.

#### Rebuild sorbet/rbi/dsl

In a terminal in the Monolith codespace, run tapioca to rebuild ALL the sorbet generated files.  _NOTE: The tapioca utility does not have a way to specify all classes in a module.  You can only run it on one class or all classes._

```
./bin/tapioca dsl
```

This generates specific signatures for class defined methods.

If only one or a few classes changed, you can run this script faster by identifying specific classes to process.

```
./bin/tapioca dsl OSSLicenseCompliance::V0::GetEnterprisePolicyRequest
```

### Check out your changes

You should now be able to interact with your changes to this gem in the Monolith codespace.

## Running Buf checks locally

Our [Buf CI action](.github/workflows/protobuf-ci.yml)
Install from [here](https://buf.build/docs/cli/installation/)

Buf formatting
The CI will complain about badly formatted protos.
Run formatter to auto format
```
buf format -w
```
Can also add plugin to your editor of choice.

Buf linting
```
cd /proto # run from /proto
buf lint
```

Buf breaking change
```
cd /proto # run from /proto
buf breaking --against '../.git#branch=main,subdir=proto'
# for more complete error
buf breaking --against '../.git#branch=main,subdir=proto' --error-format=json | jq .
```

Can run both buf linting and breaking with
```
make lint
```
