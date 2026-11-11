# dependency-graph-platform-proto
Home for Twirp RPC protobuf specs and generated code owned by and exported from the [Dependency Graph Platform](https://github.com/github/dependency-graph-platform) project. For Hydro or Aqueduct Bridge protobufs owned by DGP, visit the [Hydro GitHub app](https://hydro.githubapp.com) and the `hydro-schemas` repository.

If you'd like to propose a new access pattern for the Dependency Graph, or you have questions about a current one, please file an Issue or PR here to start the conversation, or ping us directly in `#dg-engineering`


## Development

Our ProtoBuf code is generated on PRs by the [Buf CI action](.github/workflows/protobuf-ci.yml).
This runs linting and breaking change detection, if this passes it will
generate and commit the proto Go and Ruby code.

Our buf lint and breaking change config is in `proto/buf.yaml`
To run this locally see [Running Buf locally](#running-buf-checks-locally)

### Creating or updating protobufs for the DGP project

- Update or create new `.proto` files in the `/proto` directory, under the appropriate subdir tree
  - Select an appropriate output subdir to set as the `go_package` when composing new `.proto` files (see prior art)
  - Advise to run buf format locally to ensure protos are in correct format [Running Buf locally](#running-buf-checks-locally)
- Create PR to trigger [Buf CI action](.github/workflows/protobuf-ci.yml) this will:
  - Run linting
  - Run backward compatibility check
  - Generate proto Ruby and Go code
- Recommended to ensure proto code works as expected see [Testing PR generated proto](#testing-pr-generated-proto)
- Obtain approval
- Merge PR

* Don't forget to:
  * Create a PR to update the DGP monolith Gem, if needed once the DGP PR lands

NOTE: When importing the generated Twirp code to your project, the import path will be:
`github.com/github/dependency-graph-platform-proto/gen/go/twirp/v1/<go_package>`

### Testing PR generated proto

If you would like to test the proto generated code before merging the PR.

Obtain ref from PR with generated code

*In Go projects:*

```
go get github.com/github/dependency-graph-platform-proto@<commit || branch>
```

Check go.mod has updated

*In Ruby projects:*

In Gemfile have 2 options.

```
# using commit in ref
gem "dependency-graph-platform-proto", github: "github/dependency-graph-platform-proto", ref: "<commit>"


# Using branch
gem "dependency-graph-platform-proto", github: "github/dependency-graph-platform-proto", branch: "my-proto-pr-branch"
```

Then vendor gem as below.

### How do I package and vendor the DGP gem into the monolith codebase?
Prerequisites:
* Your `dependency-graph-platform-proto` changes should already be landed
* Associated `dependency-graph-platform` handler changes should be landed, or DGP redeployed, to pick up generated code changes

1. Spin up a monolith Codespace
1. Create the branch you'll PR the Gem update against
1. Run the `vendor-gem` script from the monolith repo checkout as shown below

```
# From the monolith checkout root:
script/vendor-gem -r main -p . -n dependency-graph-platform-proto https://github.com/github/dependency-graph-platform-proto
```
Note: `script/vendor-gem` has been [deprecated](https://github.com/github/ruby-architecture/discussions/1027) in favor of [Bundler](https://bundler.io/guides/git.html) 

* Update the Gemfile to use the newer version of `dependency-graph-platform-proto`
```
# Old gem reference with outdated commit SHA
- gem "dependency-graph-platform-proto", github: "github/dependency-graph-platform-proto", ref: "abc123"

# New gem reference with updated commit SHA
+ gem "dependency-graph-platform-proto", github: "github/dependency-graph-platform-proto", ref: "def456"
```
* After updating the Gemfile, run the following command to fetch updated gem

```bundle install```

* Rebuild sorbet RBI files

```./bin/tapioca gem dependency-graph-platform-proto```


_Don't forget to check in the generated code and PR it on the monolith repo!_


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

## What if I need to add a breaking change?

We should only do this in exceptional circumstances

We can ignore the file in proto/buf.yaml
We already do this for `v1/experimental`
Please remove the ignore in a separate PR after the merge.

