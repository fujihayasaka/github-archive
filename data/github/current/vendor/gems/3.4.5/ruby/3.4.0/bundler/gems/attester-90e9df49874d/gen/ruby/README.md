# `monolith-twirp-attester`

This is the Ruby client that `github/github` (AKA `dotcom`) uses to talk to the
`attester` service.

## Set-up

The `monolith-twirp-attester` gem depends on
[`sigstore-proto`](https://github.com/github/sigstore-proto/pkgs/rubygems/sigstore-proto)
which is hosted in GitHub Packages. To install gems from GitHub packages, you'll
need to create a personal access token with the `packages:read` scope and then
run the following:

```
bundle config https://rubygems.pkg.github.com/github USERNAME:TOKEN
```

Install all of the project dependencies with the following:

```
bundle install
```

## Updating

Generate a Ruby client from the Attester protobuf definitions by running the
following from the project root:

```
make generate-ruby
```

Update Sorbet types with the following commands:

```
rake tapioca
```

Check sorbet types by running the following:

```
rake srb
```

## Testing

### Live Testing

To run tests agains a live, local instance of `attester`, first start the
server:

```
make dev-server
```

Then run the Ruby tests with the following:

```
bundle exec rake test-live
```

### Mocked Testing

To run tests against the VCR-recorded responses simply run:

```
bundle exec rake test
```

With the recorded response there is no need to start the TMA server.
