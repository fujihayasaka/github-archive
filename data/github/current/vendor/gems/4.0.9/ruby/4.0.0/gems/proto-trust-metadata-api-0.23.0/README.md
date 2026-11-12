# Proto::TrustMetadataApi::Client

This is the Ruby client that `github/github` (AKA `dotcom`) uses to talk to the
`trust-metadata-api` service.

See the [dev-dotcom](../../docs/dev-dotcom.md#updating-the-tma-ruby-gem) docs
for details about working with this Ruby gem.

## Updating

You need to [configure authentication](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-rubygems-registry#authenticating-with-a-personal-access-token) with GitHub Packages to install gems stored
on `rubygems.pkg.github.com/github`

Edit the `SIGSTORE_COMMIT` to match the latest tagged version of [sigstore/protobuf-specs](https://github.com/sigstore/protobuf-specs) in the [Makefile](../../Makefile)

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

Update the gem version in [ruby/trust-metadata-api/lib/proto/trust-metadata-api/version](./lib/proto/trust-metadata-api/version.rb) and the changelog in [ruby/trust-metadata-api/CHANGELOG.md](./CHANGELOG.md).

Once you're happy with the changes and ready for a pull request, run
```shell
bundle install
bundle exec rake build
```

You should see a new file in `ruby/trust-metadata-api/pkg` with the new gem version. This confirms the gem version was created successfully.

The Gemfile.lock file should also have been updated with the new gem version. Commit the Gemfile.lock change and create a pull request.

When you're ready to publish the new gem to the [package registry](https://github.com/github/trust-metadata-api/pkgs/rubygems/proto-trust-metadata-api), manually execute the [Publish Ruby Gem](https://github.com/github/trust-metadata-api/actions/workflows/publish-gem.yml) workflow. 


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

To reset the database and server after a test run:

```
make dev-migrate-reset && make dev-server
```

### Mocked Testing

To run tests against the VCR-recorded responses simply run:

```
bundle exec rake test
```

With the recorded response there is no need to start the TMA server.
