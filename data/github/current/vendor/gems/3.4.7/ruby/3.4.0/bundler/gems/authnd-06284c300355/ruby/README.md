# Authnd Ruby Client

A Ruby client to interact with the `authnd` RPC API.

## Usage

See [Ruby Client Docs](https://thehub.github.com/engineering/development-and-ops/authentication/authnd/ruby-client).

### Developing & Testing

First, bootstrap the repository:

```shell
script/bootstrap --ruby && bundle install
```

- If you run into the error `bundle: command not found` while running this command, install the bundler gem first by running `gem install bundler`

- If you run into an error saying:
```
An error occurred while installing byebug (11.1.3), and Bundler cannot continue.
Make sure that `gem install byebug -v '11.1.3' --source 'https://rubygems.org/'` succeeds before bundling.
```
 
- Do `rbenv install 3.4.1` followed by `gem install pry-byebug`

---

To generate ruby client code from protobuf files:

```shell
make protoc
```

To run a linter on the ruby-client code:

```shell
make ruby-client-lint
```

To run unit tests for the ruby-client code:

```shell
make ruby-client-tests
```

To run unit AND integration tests for the ruby-client code:

```shell
INTEGRATION=1 make ruby-client-tests
```

To lint, unit test, and integration test the ruby-client code:

```shell
INTEGRATION=1 make ruby-client
```

To run unit AND integration tests for the ruby-client code and view test coverage:

```shell
COVERAGE=1 INTEGRATION=1 make ruby-client-tests
```

To run a single test file:

```shell
ruby path/to/file/test_file.rb
```

### Releasing

#### Creating a new release

1. Bump version in `ruby/lib/authnd/version.rb`
1. Update [ruby/CHANGELOG.md](./CHANGELOG.md)
1. Commit and merge your changes to `main`
1. Once your changes are in `main`, check out `main` and run `make ruby-client-release` to create the Git tag, push it, and create a release.

We don't currently produce Gems and publish them anywhere, so the tag should be used to vendor the gem into whatever repo is using it.

#### Using a release in github/github

1. From the `github/github` repo, update the `ref` for the `authnd-client` gem ([ref](https://github.com/github/github/blob/0ab85ee85c7a7560b99570930ac80921900b5165/Gemfile#L37))
1. Run `bin/bundle`
1. Add the adjustments needed in your codebase
1. Open PR on `github/github` and make sure all is green

### Local testing with dotcom

If you are making local changes, commit them to a branch, and push it to `github/authnd`. Then follow the steps for "Using a release in github/github" above.

**Do not merge** the vendored Gem to dotcom's `master`.
We only want to use properly-released versions in dotcom deployments.
