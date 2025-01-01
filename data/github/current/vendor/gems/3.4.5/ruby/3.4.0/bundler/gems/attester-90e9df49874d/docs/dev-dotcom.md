# Development with Dotcom

## Table of Contents

- [Dotcom (github/github)](#dotcom-githubgithub)
- [Updating the Attester Ruby Gem](#updating-the-attester-ruby-gem)
- [WIP: Updating github/github](#wip-updating-githubgithub)

## Dotcom (github/github)

The easiest path to working with `dotcom` and microservices that it uses is to
use Codespaces.

1. Go to the `dotcom` [repo](https://github.com/github/github)
1. Click on the `Open in GitHub Codespaces` button
1. Click `Create Codespace` and wait for the Codespace to be created

This will boot a Codespaces instance with `dotcom` and all of its dependencies.
You can then run `script/server` to start the server. It should be available at
`github.localhost`.

You can read more about developing `dotcom` on
[The Hub - dotcom development](https://thehub.github.com/epd/engineering/products-and-services/codespaces/dotcom-development/).

> You can open the dotcom codespaces in your local VS Code by clicking on the
> `Open in VS Code` button in the Codespaces UI.

## Updating the Attester Ruby Gem

If you need to update the Attester Ruby Gem, you can do the following.

> [!NOTE] As long as you have Ruby installed, these steps can be run on your
> local machine.

First, we're going to build the gem locally. Make sure your `attester` local
copy is up to date.

```shell
# update the attester
git pull

# checkout a new branch
git checkout -b update-attester-gem-v0-X-0
```

This should have been done when the Attester protobuf files were updated but
ensure we have the latest
[sigstore/protobuf-specs](https://github.com/sigstore/protobuf-specs) files:

1. Edit the `PROTO_SOURCE_REF` to match the latest tagged version of
   [sigstore/protobuf-specs](https://github.com/sigstore/protobuf-specs) in the
   `Makefile`
1. `make update-proto-files`

Generate the new Ruby protobuf files. This will create a new Docker image and
generate the protobuf/twirp ruby files.

```shell
script/generate-ruby-protobuf-files
```

Make sure to update the gem version in
`ruby/attester/lib/proto/attester/version` and the changelog in
`ruby/attester/CHANGELOG.md`.

Once you're happy with the changes, create a pull request and get it reviewed.
Once it's merged you can build a new gem locally:

```shell
cd ruby/attester

bundle install
bundle exec rake build
```

You should see a new file in `ruby/attester/pkg` with the new gem version.

## Updating github/github

Once you have merged gem changes into our default branch, you will need to bump
dotcom to make any new features available.

Use the instructions above to create a `dotcom` codespace and add
`proto-attester` so you can test the changes.

Open the `Gemfile` for `github/github` and locate the entry for
`proto-attester`. Update the `ref` value to point at the latest commit SHA in
the `github/attester` repository:

```
gem "proto-attester", github: "github/attester", ref: "4bab1843702bc3a3657d1823821841530ad521f3", glob: "ruby/attester/*.gemspec"
```

Run `bundle install` to vendor the attester gem.

On top of that, you'll also need to run

```bash
bin/rails db:migrate db:test:soft_reset; bin/tapioca dsl
```

and commit the result to update sorbet definitions.

When everything is tested and working, create a pull request and get it
reviewed. Once it's merged, you can deploy `dotcom` to production.
