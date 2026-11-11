# Updating Twirp-based dotcom interfaces

This doc was inspired by https://github.com/github/copilot-api/blob/main/docs/dev/monolith-twirp.md. 

> [!WARNING]
> The default choice for getting data is our public [REST](https://docs.github.com/en/rest) and [GraphQL](https://docs.github.com/en/graphql) APIs over bespoke Twirp RPCs. Among the benefits are higher per user rate limits, in place CAP filtering, better visibility, wider maintainability, and significantly easier development and deployment. Wherever possible, try to use the public APIs. When in doubt, ask for guidance. Make sure that [internal communication with Twirp](https://thehub.github.com/epd/engineering/products-and-services/dotcom/internal-api-communication/) is the right tool for your use case!

## To Twirp or Not To Twirp

In the course of developing in sweagentd you may need to write code that gets data from dotcom.

If the data you need is already available via our public [REST](https://docs.github.com/en/rest) and [GraphQL](https://docs.github.com/en/graphql) APIs, see this [discussion](https://github.com/github/copilot-core-productivity/discussions/1829) for examples, and feel free to skip the rest of this document.

If the data you need isn't available via the public APIs, please consider adding it. The effort to add a new field or GraphQL operation is comparable to that of adding to the Twirp RPCS, and will benefit all customers. Migrating an existing Twirp RPC is also pretty straightforward.

If the data you need can't be part of the public APIs, for example to do bespoke authorization checks or to fetch non-public data, one option is to use Twirp gems, which expose interfaces specific to clients' needed access to dotcom internals; they:

1. are defined (with `services` in `.proto` files) in client projects, not dotcom
2. these service interfaces are compiled into gems and uploaded by Octofactory
3. these gems are then pulled from Octofactory and vendored into dotcom.

In general, our Twirp interfaces consist of:

1. A schema definition (`.proto` files in `sweagentd`)
2. A server-side handler (the `_handler.rb` file in Dotcom)
3. A client implementation (in `sweagentd`)

### Add A New Twirp RPC

Adding a new Twirp RPC has three distinct steps:

- Updating the schema definitions for the RPC (these live in `sweagentd`)
- Adding a server implementation for the new definition (this is in dotcom)
- Using your new RPC to fetch data in `sweagentd`

#### Updating schema definitions

This is a process that involves updating the [proto definitions](https://github.com/github/sweagentd/tree/main/proto) in **proto/sweagentd**,
updating the client gem and write the actual implementation in dotcom, consume the new RPC
back in `sweagentd`.

#### Adding the server implementation

Our server implementations live in the dotcom monolith so they can easily access dotcom data. You'll need to add the new RPC logic in the [`sweagentd_api_handler.rb`](https://github.com/github/github/blob/175976b8390cf7cbdfe27c0b32bc78c6ece4ff28/app/api/internal/twirp/sweagentd/sweagentd/v1/sweagentd_api_handler.rb).

#### sweagentd implementation

After you've updated the schema and implemented the handler in dotcom, you can begin to implement the methods to use your new RPC.

### Updating Twirp definitions

You can add new fields to an existing Twirp RPC using the same process as above. Note that, because fields are optional and have default values unless otherwise specified (see [Twirp Docs][twirp-docs-default-values]), you can typically safely add fields to the schema definition and client fetcher at the same time, then add the handler in dotcom. Your new fields will simply use the default `null` value until you update your handler.

## Adding a new monolith-twirp interface

_On the sweagentd side:_ ([example PR](https://github.com/github/sweagentd/pull/7628))

1. Define that a new service request/response type in an appropriate location in `proto/sweagentd` and its associated data types.
2. Generate new `.pb.go` files by running `make proto`.
3. In the VERSION file under the `/proto/$COMPONENT` path, bump the version in accordance with semver principles. 
4. Commit and merge your patch once it's approved.
5. In the resulting build log, verify that the version has been bumped to your new version and that version has been uploaded to Octofactory.

_On the dotcom side:_ ([example PR](https://github.com/github/github/pull/405028))

1. Boot up a codespace.
2. Run `dev-vpn connect` to login to the VPN. Enter your dotcom password when prompted, then complete the FIDO authentication.
3. Log into Octofactory via Okta. You must be connected to the dev VPN to do this, see [these instructions](https://thehub.github.com/security/security-operations/developer-vpn-access/) for access
4. Generate an Octofactory token by following [these instructions](https://github.com/github/octofactory/blob/main/docs/usage/access.md#get-a-token).
5. Enable Bundler to connect to Octofactory with your token by running `bin/bundle config https://octofactory.githubapp.com/artifactory/api/gems/monolith-twirp-gems-releases-local $GH_USERNAME:$OCTOFACTORY_TOKEN`.
6. Download the new gem version in your codespace with `script/vendor-monolith-twirp-gem sweagentd $COMPONENT $NEW_VERSION`.
7. Wait for ages as the monolith recompiles and generates `.rbi` stubs for the gem.
8. Run `bin/rails db:migrate db:test:soft_reset; bin/tapioca dsl` to mollify dotcom CI.
9. `git add` the new files and `git rm` the files associated with the older version of a gem.
10. Implement the dotcom-side endpoint. The endpoint will be located at `app/api/internal/twirp/sweagentd/sweagentd/v1/sweagentd_api_handler.rb`.

## Updating monolith-twirp interfaces

You can add new fields to an existing Twirp RPC using the same process as above. Note that, because fields are optional and have default values unless otherwise specified (see [Twirp Docs][twirp-docs-default-values]), you can typically safely add fields to the schema definition and client fetcher at the same time, then add the handler in dotcom. Your new fields will simply use the default `null` value until you update your handler.

You may need to run `bin/tapioca gem monolith-twirp-sweagentd-$COMPONENT` after vendoring the new gem version.

[twirp-docs-default-values]: https://twitchtv.github.io/twirp/docs/best_practices.html#default-values-and-required-fields

## Testing Chat Twirp Changes Locally

If you want to test your end-to-end changes when adding or updating twirp interfaces, you can build twirp gems locally for use in a local github/github. 

- Make changes to your `.proto` files in `sweagentd/proto`. Remember to update the VERSION.
- Run `make proto` to generate new `.pb.go` `sweagentd` files
- Run the following script to generate a twirp gem with your updated changes. Your gem will appear in `tmp/monolith-twirp-sweagentd-sweagentd`
```
mkdir -p tmp/monolith-twirp-sweagentd-sweagentd

docker run -e NAMESPACE=sweagentd \
  -e MODULE_ROOT=proto \
  -e NWO=github/sweagentd \
  --volume $(pwd):/repo \
  --volume $(pwd)/tmp/monolith-twirp-sweagentd-sweagentd:/docker-build-artifacts \
  ghcr.io/github/monolith-twirp-tools/gen-ruby:latest generate
```
- Copy the twirp gem to the `vendor/cache` directory of `github/github`
```
cp ./tmp/monolith-twirp-sweagentd-sweagentd/gems/monolith-twirp-sweagentd-sweagentd-<VERSION>.gem /workspaces/github/vendor/cache/
```
- Update the Gemfile in `github/github`
- Run `script/bootstrap` in `github/github` to update the `Gemfile.lock`
- Test out your changes!
