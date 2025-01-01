# Run Billing Platform in a Dotcom codespace

Billing Platform can be run inside Dotcom to develop end-to-end features.

## Table of Contents

- [Terminology](#terminology)
- [Details](#details)
  - [Codespace setup instructions](#codespace-setup-instructions)
  - [Making changes to Billing Platform](#making-changes-to-billing-platform)
  - [Testing changes to the Ruby client](#testing-changes-to-the-ruby-client)
  - [Codespace secrets](#codespace-secrets)
- [Troubleshooting](#troubleshooting)
  - [Ports in use](#ports-in-use)
  - [Can't connect to aqueduct](#cant-connect-to-aqueduct)
  - [RESULT_FAILED_ACCESS_TOKEN_NOT_FOUND](#result_failed_access_token_not_found)
- [References](#references)

## Terminology

- **Common term**: definition

## Details

### Codespace setup instructions

1. Follow the github/github paved path [doc](https://thehub.github.com/epd/engineering/products-and-services/codespaces/dotcom-development/) on how to set up your development enviroment using Codespaces and VS Code. Reach out to [#dotcom-codespaces](https://github.slack.com/archives/C01S7MANE30) slack channel with any issues
1. Start dotcom with `script/server`
1. Open another terminal window
1. Clone billing-platform with `script/setup-codespaces-billing-platform`
   - Answer `y` at the `Do you want to continue?` prompt
1. Move into billing-platform with `cd ../billing-platform`
1. Start billing-platform with `script/server`
1. To onboard a customer to billing platform in development, you can use this Stafftools page (http://github.localhost/stafftools/billing/onboard_billing_platform_customer). The customer id for the GitHub enterprise in development is 1.

If you'd like to see at a glance whether the integration is working, you can run `script/produce` from `/workspaces/billing-platform/` at this point, to generate billable usage data. It should be viewable in the UI at [/enterprises/github-inc/billing](http://github.localhost/enterprises/github-inc/billing).

### Making changes to Billing Platform

Sometimes it's necessary to use a Dotcom codespace in order to test Billing Platform changes end-to-end. While you could make changes in a separate Billing Platform codespace, the process would be tedious and cumbersome. If you're using VSCode you can instead add Billing Platform to your workspace within the Dotcom codespace that will allow you to make changes to Billing Platform code directly.

1. Open the github/billing-platform workspace file:
    ```sh
    code /workspaces/billing-platform/.vscode/github-billing-platform.code-workspace
    ```
1. At this point you should see both `github/` and `billing-platform/` working directories.

You should now be able to search for code and make code changes within the `billing-platform` project. One caveat is that you may need to restart your Billing Platform server in order for changes to take effect.

> [!NOTE]
> Dotcom codespaces seem to be missing an authorization token that's required in order to download Go packages. This prevents you from downloading any new packages, updating existing packages, and as a result you will also be unable to run integration tests from within the Dotcom codespace.

### Testing changes to the Ruby client

Once you have a billing-platform branch created with changes to the client, follow these steps to vendor and test a local gem version in dotcom:

- Checkout your billing-platform changes in a [Dotcom codespace](#codespace-setup-instructions).
  - Note: Your changes must be commited and pushed to a remote branch in billing-platform for Bundler to successfully locate the changes.
- Update the Gemfile in dotcom with a reference to the updated client in your remote branch by replacing the `billing-platform-client` gem entry with `gem "billing-platform-client", github: "github/billing-platform", ref: "<GIT REF>"`.
  - You can get the latest git ref of your branch by running `git log` in the billing-platform directory (it will look something like `b8325b019ca8e579a4ff804dc477cfb976199aab`).
- Run `bundle install`
- Test the updated client changes in dotcom.

### Codespace secrets

We are using [dotcom Codespaces secrets](https://github.com/github/github/settings/secrets/codespaces) to store `DEV_COSMOS_KEY`, `AZURE_COMMERCE_SPN_CLIENT_SECRET`, and `ZUORA_*` variables so the `billing-platform` application can work out-of-box. The values should be kept in sync with [billing-platform Codespaces secrets](https://github.com/github/billing-platform/settings/secrets/codespaces). Follow the [JIT sessions for GitHub Org admin](https://thehub.github.com/security/security-operations/jit/org-admin/) article to get access to the `github/github` org settings.

## Troubleshooting

### Ports in use

Errors like these pop up from time to time:

```bash
Error starting userland proxy: listen tcp4 0.0.0.0:6379: bind: address already in use

Error starting userland proxy: listen tcp4 0.0.0.0:18081: bind: address already in use
```

It's likely that either Dotcom is running a service that's using this port,
or a background process from billing-platform is still running.

To resolve this, first check if there are Docker containers running in the background,
and optionally stop them:

```bash
docker-compose ls
docker-compose stop
```

Specifically if the issue comes from Redis, you can run:

```bash
sudo pkill redis-server
```

### Can't connect to aqueduct

```bash
dial tcp [::1]:18081: connect: connection refused
```

Likely this means that Dotcom isn't running. Make sure you've run `script/server`
in Dotcom before attempting to start `billing-platform`.

### RESULT_FAILED_ACCESS_TOKEN_NOT_FOUND

Running `script/setup-codespaces-billing-platform` or `script/server` in billing platform, fails with error `RESULT_FAILED_ACCESS_TOKEN_NOT_FOUND` when trying to talk to `https://goproxy.githubapp.com`

This has turned up a hand full of times, some possible solutions are:

- Running `script/source-goproxyenv`
- Starting a brand new codespace

## References

- [Actions Usage Ingestion](/docs/how-to-guides/how-to-ingest-actions-usage.md)
- [Scripts to generate usage and rollups](/docs/how-to-guides/how-to-generate-mock-usage.md)
