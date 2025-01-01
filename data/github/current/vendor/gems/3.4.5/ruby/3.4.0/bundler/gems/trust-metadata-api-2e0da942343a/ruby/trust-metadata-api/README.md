# Proto::TrustMetadataApi::Client

This is the Ruby client that `github/github` (AKA `dotcom`) uses to talk to the
`trust-metadata-api` service.

See the [dev-dotcom](../../docs/dev-dotcom.md#updating-the-tma-ruby-gem) docs
for details about working with this Ruby gem.

## Updating

You need to [configure authentication](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-rubygems-registry#authenticating-with-a-personal-access-token) with GitHub Packages to install gems stored
on `rubygems.pkg.github.com/github`

Generate a Ruby client from the TMA protobuf definitions by running the
following from the project root:

```shell
make generate-ruby
```

Update and check Sorbet types with the following commands:
```shell
# update sorbet types
bundle exec tapioca dsl
bundle exec tapioca gems
bundle exec tapioca annotations
# check sorbet types
bundle exec srb tc
```

## Testing

### Live Testing

To run tests against a live, local instance of `trust-metadata-api`, first start
the server:

```
make dev-start && make dev-migrate-up && make dev-server
```

Then run the Ruby tests with the following:

```
bundle exec rake test-live
```

To reset the database after a test run:

```
make dev-migrate-reset
```

### Mocked Testing

To run tests against the VCR-recorded responses simply run:

```
bundle exec rake test
```

With the recorded response there is no need to start the TMA server.
