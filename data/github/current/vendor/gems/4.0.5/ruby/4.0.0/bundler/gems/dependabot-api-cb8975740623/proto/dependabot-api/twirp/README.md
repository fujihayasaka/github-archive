# proto/twirp
This directory contains the [Protocol Buffers][protobuf-docs] that [Twirp][twirp-docs] relies on to expose RPC services.

[protobuf-docs]: https://developers.google.com/protocol-buffers/
[twirp-docs]: https://twitchtv.github.io/twirp/docs/intro.html

## Code generation

After updating the Procol Buffer definitions, run `script/protoc` in the repo root to generate Twrip and Protocol Buffer code.

## Bumping gem versions

Despite this being an internal gem, we try to maintain version hygiene and bump the minor version for every change.

## Updating github/github

> [!Note]
> We no longer use `script/vendor-gem`, it has been removed ([see PR](https://github.com/github/github/pull/400642)).  
> This new process ensures that the dependency is tracked precisely and reproducibly through the Gemfile and Bundler cache.

Once you have merged gem changes into our default branch including the gem version bump, update the dependency in `github/github` to point to the latest commit from `github/dependabot-api` using a Bundler git source. This process is documented in [github/github#401925](https://github.com/github/github/pull/401925).

1. In `github/github`, open the `Gemfile`.
2. Locate the relevant `gem "proto-dependabot-api"` entry.
3. Update it to point to the latest commit and Ruby gemspec, for example:

    ```ruby
    gem "proto-dependabot-api", git: "https://github.com/github/dependabot-api.git", ref: "7d7023aea9cdcbb0fdda7ba817993faa4143af5f", glob: "gen/ruby/*.gemspec"
    ```

    Replace the `ref:` value with the commit SHA of your change in `github/dependabot-api`.

4. Run:

    ```bash
    bundle install
    ```

    Bundler will fetch the entire repository at the specified commit and cache it in `vendor/cache/`, e.g. `vendor/cache/dependabot-api-7d7023aea9cd/`. This ensures reproducible builds and makes the gem available for deployment.

5. You’ll also need to update Sorbet definitions and migrations:

    ```bash
    bin/rails db:migrate db:test:soft_reset
    bin/tapioca dsl
    ```

    Commit any resulting changes.

## Updating other projects

We currently do not have any other client projects, but the `vendor-gem` script is generally common to our projects.

We may move to building the gem for [Octofactory](https://octofactory.githubapp.com/artifactory/webapp/#/home) (Developer VPN required) in the future as a distribution path.
