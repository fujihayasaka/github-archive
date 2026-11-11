# Getting Started with Spokes Access API

## Development on your laptop

1. Clone this repository. `git clone https://github.com/github/spokes-proto`
1. Log in to [GitHub Package Registry](https://ghcr.io). `docker login ghcr.io`
    * If you haven't done this before, you first need to
    [generate a personal access token](https://github.com/settings/tokens/new) with the
    `read:packages` scope enabled. You also need to `Enable SSO` on the PAT, or else it will let you log in but fail when pulling images.
    * Copy the generated token immediately!  We recommend you save it in a password keeper like
    1Password in case you need to log in again.
    * `docker login ghcr.io` with your username and for the password, enter the new personal access token you just generated.
1. Bootstrap the test environment. `script/bootstrap`
1. Start the services. `docker compose up -d` (Note: you may need to run this a couple of times, because spokesd will crash if it starts before mysql is all the way started.)

:tada: You're all set! You can now create Spokes Access API [clients](https://github.com/github/spokes-proto/tree/main/gen) using `http://127.0.0.1:12080` as the base URL. Or, try one of the example client programs in `examples/`.

The dev environment includes one repository:

- Repository ID 1: https://github.com/git-tfs/git-tfs.github.com

You can add more by using `script/clone-repo URL`.

### Updating spokesd or gitrpcd

Updating spokesd and gitrpcd is a manual process.

* To update to the newest main version of both, run `script/update-images`. *If this makes any changes, please open a PR so that everyone will get the update.*
* To update to a local dev version, build a docker image, configure it in `.env`, and run `docker compose up -d` to get it running.
    - gitrpcd
        - Build an image with gitrpcd's `script/build`.
        - Add `GITRPCD_IMAGE=gitrpcd-cibuild` to `.env`.
    - spokesd
        - Build an image with spokesd `docker build -t spokesd .`.
        - Add `SPOKESD_IMAGE=spokesd` to `.env`.

## Production

### Authentication

> [!Note]
> Proxima environments utilize Istio Service Mesh mTLS for authentication, eliminating the need to manually create certificates.
> 
> For more information, please refer to the [documentation on The Hub](https://thehub.github.com/epd/engineering/products-and-services/internal/moda/service-mesh/onboarding/#change-client-moda-urls-to-mesh-urls).

Spokes Access API clients authenticate with a TLS client certificate or with a [Request-HMAC](https://thehub.github.com/epd/engineering/dev-practicals/secure-coding/secure-coding-general/service-to-service-auth/) header.

In dev:
- `127.0.0.1:12080` requires no authentication. We recommend using this for dev.
- `127.0.0.1:12443` requires a TLS client certificate. Use [`script/generate-certs`](../../script/generate-certs) to generate certs for "test-client" in `certs/`. We recommend using this only when manually verifying client TLS code.
- `127.0.0.1:12081` requires a `Request-HMAC` header, using the hmac key "spokes-proto-hmac-key". We recommend using this in dev only if the client is unable to use a TLS client cert for auth in prod.

See the [examples](../examples/) for Ruby and Go examples of how to set up client certs or the `Request-HMAC` header.

- The first step to do so, is to add a client for staging and production in [`cmd/spokesd/application.go`](https://github.com/github/spokesd/blob/1f0e29b415d97efbb1abb172dab1cf7f029728c8/cmd/spokesd/application.go#L53-L67), open up a pull request and ask for approval on [`#spokes-api`](https://github.slack.com/archives/C01AM9W2TN0).

#### TLS client certificate

- Authenticating against `spokesd` in staging and production (when using the `:100xx` ports) requires that you set up certificates that it'll recognize.  Certs should go into the spokesd vault, and get federated from there into the client app vault.
  - Create a key per environment. Someone with access to the spokesd vault should do this from a spokes-shell host:

```bash
. vault-login
spokesctl certificates generate-client-certificate appname-production --output-cert-file appname-production.crt --output-key-file appname-production.key
vault-secret --application spokesd --environment production --key APPNAME_PRODUCTION_SPOKESD_CLIENT_CERT --value-from-file appname-production.crt --newline-override
vault-secret --application spokesd --environment production --key APPNAME_PRODUCTION_SPOKESD_CLIENT_CERT_KEY --value-from-file appname-production.key --newline-override
```

If the client app has another environment like `staging`, you should generate a cert for that environment too (but it should still go in spokesd's production vault):

```bash
. vault-login
spokesctl certificates generate-client-certificate appname-staging --output-cert-file appname-staging.crt --output-key-file appname-staging.key
vault-secret --application spokesd --environment production --key APPNAME_STAGING_SPOKESD_CLIENT_CERT --value-from-file appname-staging.crt --newline-override
vault-secret --application spokesd --environment production --key APPNAME_STAGING_SPOKESD_CLIENT_CERT_KEY --value-from-file appname-staging.key --newline-override
```

Then make a secrets-federation PR to federate the cert and key into the client app's vault.  For examples see:  [Centralize Spokesd client certificate management](https://github.com/github/git-systems/issues/5166)

The keys can then be loaded and used for TLS configuration. For an example in Go, have a look at [`examples/go`](../examples/go) or [`token-scanning-service`](https://github.com/github/token-scanning-service/blob/36fbe730d7cd8b2cdbb95ebd6e0b990b9bd9db5f/token-scanning/spokes/spokes.go#L168-L193). For an example in Ruby, have a look at [`examples/ruby`](../examples/ruby) or [`hamzo`](https://github.com/github/hamzo/blob/a33939b2af411f3c1a4eead92fa8a5c80e095bfb/app/lib/hamzo_spokes.rb#L109-L136).

##### Monitoring

The certificates generated for you default to expiring in 1 year, so we recommend setting up a [metric monitor](https://thehub.github.com/engineering/development-and-ops/observability/alerting/datadog-monitor-alerting/) for your service(s) to notify you when your certificates are about to expire. You can configure a metric monitor for your service using a similar configuration as follows:

```yaml
---
todo-service:
  spokesd-tls-cert:
    severity: sev1
    type: metric alert
    query: min(last_5m):min:spokesd.hours_until_certificate_expiry{tls_client:todo-service-production} < 168
    message: |-
      {{#is_warning}}todo-service's Spokesd TLS certificate will expire in 30 days, please roll the cert soon.{{/is_warning}}
      {{#is_alert}}todo-service's Spokesd TLS certificate will expire in 7 days, please roll the cert ASAP.{{/is_alert}}
    require_full_window: true
    notify_no_data: false
    critical: 168 # 1 week
    warning: 720 # 30 days
    catalog_service: todo-service
    tags: # suggestions below - adapt as appropriate
    # - service:todo-service
    # - app:todo-app
    # - team:todo-team
```

Git Systems also has centralized alerting for this, and a [Spokes Certificate Expiry dashboard](https://app.datadoghq.com/dashboard/npz-wwu-dxg/spokes-certificate-expiry?fromUser=false&fullscreen_end_ts=1767746063748&fullscreen_paused=false&fullscreen_refresh_mode=sliding&fullscreen_section=overview&fullscreen_start_ts=1767742463748&fullscreen_widget=547425895035956&refresh_mode=paused&tile_focus=547425895035956&from_ts=1763486518015&to_ts=1763500918015&live=false).

**Note**: The current setup for authentication is subject to change.

#### `Request-HMAC`

- Authenticating against `spokesd` in staging and production (when using default port) requires that you set up an HMAC key.
- Update your app to send a [`Request-HMAC`](https://thehub.github.com/epd/engineering/dev-practicals/secure-coding/secure-coding-general/service-to-service-auth/) header. See the [examples](../examples) for an example of how to do this in Ruby and Go.
- Generate a new secret, e.g. with `ruby -rsecurerandom -e "puts SecureRandom.hex(32)" > hmac-secret.txt`.
- Add the secret to your app's vault.
- Ask git-systems to add the secret to spokesd's vault. If your app is named "test-client", the secret's name should be `SPOKESD_HMAC_KEY_test_client`.

### User Agent

To help us diagnose issues and usages of our endpoints, we require that a `User-Agent: <service>/<sha>` header is sent.

### Environments

| Environment       | Base URL                                                        |
| ----------------- | --------------------------------------------------------------- |
| Staging           | `https://spokesd-staging.service.iad.github.net:10033`          |
| Production (IAD)  | `https://spokesd-production.service.iad.github.net:10013`       |
| Production (CUS)  | `https://spokesd-production.service.gc-cus-02.github.net:10013` |

### Gitmon interaction

Spokes Access API uses gitmon to keep track of and potentially delay or abort requests.  For more information see [gitmon.md](https://github.com/github/spokes-proto/blob/main/docs/gitmon.md)

### Errors

See [errors.md](errors.md) for information about the types of errors you might get from Spokes Access API.

## Client Setup

[spokes-proto](https://github.com/github/spokes-proto) defines Ruby and Go clients. This section describes how to set these up for an app that will be running in Moda.

### Moda

Store the Spokesd certs in Vault and make them available to your app as files. The examples below assume you've created the following environment variables in Vault:

- `SPOKESD_CLIENT_CERT` - content of cert created by `script/generate_cert`
- `SPOKESD_CLIENT_KEY` - content of key created by `script/generate_cert`
- `SPOKESD_CA_CHAIN` - content of [spokesd's `chain.pem`](https://github.com/github/spokesd/blob/master/config/certs/chain.pem)

### Go

The Spokes Access API client for Go uses twirp-generated clients and helpers for building request objects. See [examples/go](../examples/go) for an example, including TLS configuration.

### Ruby

The Spokes Access API client for Ruby uses twirp-generated clients, accessed from a top-level client. See [examples/ruby](../examples/ruby) for an example, including TLS configuration.
