# Development with Dotcom

## Table of Contents

- [Dotcom (github/github)](#dotcom-githubgithub)
- [Dotcom/Rails Notes](#dotcomrails-notes)
  - [Development](#development)
  - [Running Tests](#running-tests)
  - [Adding Trust-Metadata-API](#adding-trust-metadata-api-to-dotcom-codespace)
  - [Viewing Attestations UI in dotcom codespaces](#viewing-attestations-ui-in-dotcom-codespaces)
- [Updating the TMA Ruby Gem](#updating-the-tma-ruby-gem)
- [Testing on dotcom](#testing-on-dotcom)
- [Testing on dotcom with review labs](#testing-on-dotcom-with-review-labs)

## Dotcom (github/github)

The easiest path to working with `dotcom` and microservices that it uses is to use Codespaces.

1. Go to the `dotcom` [repo](https://github.com/github/github)
1. Click on the `Open in GitHub Codespaces` button
1. Click `Create Codespace` and wait for the Codespace to be created

This will boot a Codespaces instance with `dotcom` and all of its dependencies. You can then run `script/server` to start the server. It should be available at `github.localhost`.

You can read more about developing `dotcom` on [The Hub - dotcom development](https://thehub.github.com/epd/engineering/products-and-services/codespaces/dotcom-development/).

> You can open the dotcom codespaces in your local VS Code by clicking on the `Open in VS Code` button in the Codespaces UI.

## Dotcom/Rails Notes

### Development

The files that are most likely to be related to `dotcom/tma` communication can be found in the `SERVICEOWNERS` file associated with `:trust_metadata`.

---

If you want to use `binding.pry` to debug something, you can comment out `web: script/unicorn-server` in `Procfile` and run the following commands in two different terminals: `script/server` & `script/unicorn-server`. When you run your request against `dotcom`, your `pry` session will be in the `unicorn-server` terminal.

---

To active the feature flag in the development environment, you can do the following:

```ruby
bin/rails console
GitHub.flipper[:attestations_api].enable # TMA API Feature Flag
GitHub.flipper[:attestations_ux].enable  # Attestation UI Feature Flag
```

### Adding Trust-Metadata-API to dotcom Codespace

If you need to work on the Trust-Metadata-API, you can add it to your Codespace by running the [setup script](https://github.com/github/github/blob/master/script/setup-codespaces-trust-metadata-api) in the `github/github` repository:

`script/setup-codespaces-trust-metadata-api`

You should now have a running TMA server with database locally in the codespace that you can use to test your changes to `dotcom`.

---

You can use curl to test the `dotcom/tma` local development:

```shell
# Query for an attestation
curl -L \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer (REPLACE WITH DEV TOKEN)"\
  -H "X-GitHub-Api-Version: 2022-11-28" \
  http://api.github.localhost/repositories/4/attestations/sha512:7bea9f6e7ff37f5fab0b36bf061200fff03099fd2fd696b91d04bc5e4f225eb9fd6e0cadcad54ba980f43fb352a99e8810b4e0abeb5c0ef2cf9108cd1f258b36

# Create an attestation
export bundle=$(<test/fixtures/attestations/sigstorejs100_provenance_bundle.json)

curl -L \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer (REPLACE WITH DEV TOKEN)" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  http://api.github.localhost/repositories/4/attestations --data '{"subject_digest": "sha512:7bea9f6e7ff37f5fab0b36bf061200fff03099fd2fd696b91d04bc5e4f225eb9fd6e0cadcad54ba980f43fb352a99e8810b4e0abeb5c0ef2cf9108cd1f258b36", "bundle":'"$bundle"'}'
```

> You can find the development token in [`db/seeds.rb` file](https://github.com/github/github/blob/master/db/seeds.rb). The token will be `ghp_<token_suffix>`.

### Viewing Attestations UI in dotcom codespaces

- Run `bin/seed actions` to setup the `Actions` feature. (TODO, how to setup an actual runner??)
- Add a basic GitHub Actions flow if you just want to test the view:
  - `http://github.localhost/monalisa/illuminati/actions/new` or whichever repo you want on your dev instance
  - `Simple Workflow > Configure`
  - `Commit Changes`
- If you go to the repo’s `Actions` tab you should see the `Attestations` option on the left now.

### Running Tests

You can run the tests for `dotcom` by running the following command: `./bin/rails test test/file/here.rb`

```shell
# Run a specific test file:
./bin/rails test test/integration/api/attestations_test.rb

# run a specific test in the test file:
./bin/rails test test/integration/api/attestations_test.rb:LINE_NUMBER_OF_TEST
```

If you need to focus on one test at a time, you can add `skip` to the other tests in the file and then remove the `skip` from the test you want to run.

### Troubleshooting steps

- Error: "Authentication failed reading `https://goproxy.githubapp.com/*`"
  - Try creating a fresh Codespace: Codespaces automatically sets up a [GitHub Application token](https://github.com/github/authnd/blob/main/docs/db-schema.md#user-to-server-tokens) to [authenticate with the Go Proxy](https://github.com/github/goproxy/blob/main/doc/user.md#authentication-token), but it seems this token can expire after a few days (?)

## Updating the TMA Ruby Gem

If you need to update the TMA Ruby Gem, you can do the following.

> [!NOTE]
> As long as you have Ruby installed, these steps can be run on your local machine.

First, we're going to build the gem locally. Make sure your `trust-metadata-api` local copy is up to date.

```shell
# update the trust-metadata-api
git pull

# checkout a new branch
git checkout -b update-tma-gem-v0-X-0
```

This should have been done when the TMA protobuf files were updated but ensure we have the latest [sigstore/protobuf-specs](https://github.com/sigstore/protobuf-specs) files:

1. Edit the `PROTO_SOURCE_REF` to match the latest tagged version of [sigstore/protobuf-specs](https://github.com/sigstore/protobuf-specs) in the `Makefile`
1. `make update-proto-files`

Generate the new Ruby protobuf files. This will create a new Docker image and generate the protobuf/twirp ruby files.

```shell
script/generate-ruby-protobuf-files
```

Now that we have the latest protobuf files, you'll need to update the `proto-trust-metadata-api` gem tests. It helps to have a local copy of `tma` running so you can test your changes. Update or add tests in the `ruby/trust-metadata-api/test` directory.

You can run the tests with `bundle exec rake test`.

To regenerate the `VCR` fixtures, you can delete them and then run the tests again. The tests will generate new fixtures.

Make sure to update the gem version in `ruby/trust-metadata-api/lib/proto/trust-metadata-api/version` and the changelog in `ruby/trust-metadata-api/CHANGELOG.md`.

Once you're happy with the changes and ready for a pull request, run
```shell
cd ruby/trust-metadata-api

bundle install
bundle exec rake build
```

You should see a new file in `ruby/trust-metadata-api/pkg` with the new gem version. This confirms the gem version was created successfully.

The Gemfile.lock file should also have been updated with the new gem version. Commit the Gemfile.lock change.

Finally, create a pull request.

## Updating github/github

Once you have merged gem changes into our default branch, you will need to bump dotcom to make any new features available.

Use the instructions above to create a `dotcom` codespace and add `proto-trust-metadata-api` so you can test the changes.

Open the `Gemfile` for `github/github` and locate the entry for `proto-trust-metadata-api`. Update the `ref` value to point at the latest commit SHA in the `github/trust-metadata-api` repository:

```
gem "proto-trust-metadata-api", github: "github/trust-metadata-api", ref: "4bab1843702bc3a3657d1823821841530ad521f3", glob: "ruby/trust-metadata-api/*.gemspec"
```

Run `bundle install` to vendor the TMA gem.

On top of that, you'll also need to run

```bash
bin/rails db:migrate db:test:soft_reset; bin/tapioca dsl
```

and commit the result to update sorbet definitions.

Now that we have the updated gem, we need to update the `dotcom` logic & tests.

Most of the logic can be found in `packages/attestations/app/models/trust_metadata.rb` or `app/api/attestations.rb`. You can look at previous PRs to those files to see the other changes that were made.

You can find the tests in the `test/integration/api/attestations_test.rb` file. You'll need to update the `VCR` fixtures and the tests to use any new logic.

When everything is tested and working, create a pull request and get it reviewed. Once it's merged, you can deploy `dotcom` to production.

## Testing on dotcom

> ⚠️ This section will be changing as we develop the full end-to-end feature. This includes the endpoints and parameters changing if needed. Remove or update when it's finished (Last updated: 2023-09-29)

[Test Repo: https://github.com/github/trust-metadata-demo](https://github.com/github/trust-metadata-demo)

> The `repo_id` for `https://github.com/github/trust-metadata-demo` is `476040063`

Right now you should be able to use `gh` to test against the feature flagged attestation feature.

- Ensure `gh` is authenticated against your GitHub account: `gh auth login`
- It should have the following Token scopes when you run `gh auth status`: `Token scopes: admin:public_key, gist, read:org, repo`

Fetch an attestation by subject digest:

```
# gh api --verbose repositories/{repo_id}/attestations/{subject_digest}

gh api --verbose repositories/476040063/attestations/sha512:bbfd372fc9beeb777fe35d05bb10c0c70a9733d366a75fed7dd18866c7391de3ee7e88ba74dd47abf3e15c845e547fcf0e5c3da80854c751554224d3a6d4e55f
```

Create an attestation:

```
# gh api --verbose -X POST /repositories/{repo_id}/attestations \
# -H "Content-Type: application/json" \
# --input payload.json

# payload.json: {"bundle": CONTENTS_OF_BUNDLE_JSON}

gh api --verbose -X POST /repositories/476040063/attestations \
-H "Content-Type: application/json" \
--input payload.json
```

## Testing on dotcom with review labs

You can test your `dotcom` pull request using the Production database with a `github/github` Review Lab. The lab will be deleted after 4 hours.

> You must run this command from `#dotcom-environment-ops`

Run the following command:

```text
.deploy github/branchname to review-lab --lab <lab-name>
```

For example, if you have a `github/github` PR `#309718` and your package-security issue is `#1234`:

```text
.deploy https://github.com/github/github/pull/309718 to review-lab --lab pkgsec1234
```

Read more at [The Hub - Review Labs](https://thehub.github.com/epd/engineering/devops/deployment/environments/review-lab/).

