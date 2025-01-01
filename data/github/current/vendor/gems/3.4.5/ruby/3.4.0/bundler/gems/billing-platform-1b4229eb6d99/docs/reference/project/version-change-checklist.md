# Releasing a new version of billing platform

This document contains a checklist of all the steps to check before releasing a new version of billing-platform.

## Billing Platform Changes

1. Make the code change. In order to determine if your code change requires a version change, check out this guide on [Semantic Versioning](https://semver.org/). An example of a code change that would require a version change is adding a new API endpoint, changing the parameters of an endpoint, etc.

2. Update the necessary `.proto` files. For example if you added a new API to `lib/api/usage.go`, you will need to update `proto/usage-api.proto`.

3. Run `script/helpers/protoc` which will generate the necessary files for the change.

4. Add changes to `ruby/lib/billing-platform/client.rb`

5. Change the version in `ruby/lib/billing-platform/version.rb` according to the [Semantic Versioning](https://semver.org/) principles.

6. Test your changes in a [Dotcom codespace](../../tutorials/run-billing-platform-in-dotcom-codespaces.md#testing-changes-to-the-ruby-client).

7. Open a PR and merge your changes.

8. Once merged, CI will generate a new release tagged with the version number you set.

## Dotcom Changes

1. Update Dotcom to use the new version of the billing-platform client by updating Dotcom's [Gemfile](https://github.com/github/github/blob/master/Gemfile) `billing-platform-client` entry to reference the latest git tag in billing-platform's [releases](https://github.com/github/billing-platform/tags).
    - The entry should look similar to: `gem "billing-platform-client", github: "github/billing-platform", tag: "v0.49.0"`

2. Update/add calls to use the newly modified/added billing-platform client methods.

3. Update/add affected integration/unit tests.

4. Open a PR and merge your changes.
