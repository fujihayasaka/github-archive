# Twirp services

This folder contains definitions for Twirp services that we run in the monolith and call from TurboScan.

See the [github/monolith-twirp](https://github.com/github/monolith-twirp) repo for a lot of great documentation of how it all works.

In short:

* The proto definitions are used to generate the Go client in this repo and
* A CI job named `turboscan-monolith-twirp` takes configuration info from the [`.monolith-twirp`](https://github.com/github/turboscan/blob/main/.monolith-twirp.yml) file in the repo root and generates a Ruby gem that is put into Octofactory for use in gh/gh.
* The service handlers in gh/gh are located under [`app/api/internal/twirp/code_scanning`](https://github.com/github/github/tree/master/app/api/internal/twirp/code_scanning).

## If you need to change an existing service

1. In the Turboscan repo:
    * Update the according proto definitions
    * Run `script/protoc` to regenerate the client definitions for Turboscan.
    * Bump the version in the service's `VERSION` file. This is necessary to get the changes published to Octofactory
    * Merge the above changes into Turboscan.
Once the changes are in `main`  the CI job `turboscan-monolith-twirp` will create a Ruby gem (named e.g. `monolith-twirp-code_scanning-managed_analyses`) with the code and publish it to Octofactory.
⚠️ The job will only upload a build on a run on `main` but with the merge queue, it can be that the branch is fast-forwarded and no CI runs on `main`. You can force a run of the job with the following chatops: `.ci build turboscan-monolith-twirp`.

2. In the github/github repo:
    * Vendor the gem into github/github.
      1. Update the version of the Gem in the Gemfile.
      2. Configure Octofactory access for `bundler`
         * Connect to the developer vpn. Within a codespace you can connect via `dev-vpn connect`.
         * Generate an [Octofactory token](https://github.com/github/octofactory/blob/main/docs/usage/access.md#get-a-token)
         * Setup bundler to use the token, substituting your username and the token the following command:
           `bundle config https://octofactory.githubapp.com/artifactory/api/gems/monolith-twirp-gems-releases-local USERNAME:TOKEN`
      3. Run the vendor script. For example, `./script/vendor-monolith-twirp-gem code_scanning managed_analyses 1.0.1` updates the twirp definitions for the `managed_analyses` service to version `1.0.1`.
      4. Run sorbet changes: `bin/tapioca gem && bin/rails db:migrate db:test:soft_reset; bin/tapioca dsl`
    * If you've added a new endpoint you might want to use code generation for handler and tests.
      Run `bin/rails generate twirp --from-gem=monolith-twirp-code_scanning-managed_analyses --client=turboscan`.
      It will prompt you about overwriting existing files.
      You can either skip existing files and make the changes there by hand or merge the generated file with the previous version to not lose existing functionality.

## If you need to add a new service

You'll have to update the configuration file and create a folder with the right structure for your service.
It is suggested to follow the great instructions in https://github.com/github/monolith-twirp/blob/master/README.md
