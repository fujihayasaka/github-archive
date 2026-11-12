# dependency-graph-platform-proto
Home for Twirp RPC protobuf specs and generated code owned by and exported from the [Dependency Graph Platform](https://github.com/github/dependency-graph-platform) project. For Hydro or Aqueduct Bridge protobufs owned by DGP, visit the [Hydro GitHub app](https://hydro.githubapp.com) and the `hydro-schemas` repository.

If you'd like to propose a new access pattern for the Dependency Graph, or you have questions about a current one, please file an Issue or PR here to start the conversation, or ping us directly in `#dg-engineering`


## Usage FAQ


### How do I (re)generate protobufs for the DGP project
* Update or create new `.proto` files in the `/proto` directory, under the appropriate subdir tree
  * Select an appropriate output subdir to set as the `go_package` when composing new `.proto` files (see prior art)
* Run `./protoc`
* Don't forget to:
  * Check in the generated code with your `.proto` changes
  * Create a PR to update the DGP monolith Gem, if needed once the DGP PR lands

NOTE: When importing the generated Twirp code to your project, the import path will be:
`github.com/github/dependency-graph-platform-proto/gen/go/twirp/v1/<go_package>`


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
