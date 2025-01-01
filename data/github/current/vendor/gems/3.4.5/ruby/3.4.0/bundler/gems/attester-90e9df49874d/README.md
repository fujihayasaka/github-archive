# Attester

API for handling artifact signing metadata

- [Moda Dashboard](https://moda.githubapp.com/apps/attester)
- [Datadog Dashboard](TODO)
- [Datadog Tracer](TODO)
- [Sentry - Attester](https://github.sentry.io/projects/attester/?project=4507781727059968)
- [Splunk](<https://splunk.githubapp.com/en-US/app/gh_reference_app/search?q=search%20index%20IN(catchall)%20kube_namespace%3Dattester-*&earliest=-24h%40h&latest=now>)

staging: https://attester-staging.service.iad.github.net
production: https://attester-production.service.iad.github.net

## Prerequisites

1. Connect to the [GitHub IAD Production VPN](https://thehub.github.com/security/security-operations/production-vpn-access/).

## Steps to Test

1. **Build the Client Command**

   Run the following command to build the client:

   ```sh
   make dev-server
   ```

   This will start an instance of the server that uses a static keypair for signing.

2. **Test the Hello Endpoint in local**

   Use the following command to hit the Hello endpoint:

   ```sh

   go run script/body-hmac-request.go  -request-body '{"name": "foo"}' -request-url http://localhost:8338/twirp/attester.v0.BooAPI/HelloName -hmac-key "dotcomsecretkey"

   ```

   **Output:**

   ```sh
   {"message":"Hello, foo!"}
   ```

3. **Test the Release Endpoint in staging**

   Connect to the [GitHub IAD Production VPN](https://thehub.github.com/security/security-operations/production-vpn-access/).

   Use the following command to hit the release endpoint:

   ```
   go run script/body-hmac-request.go -request-body "{\"statement\":$(cat example/release_statement_03_06_2025.json)}" -request-url https://attester-staging.service.iad.github.net/twirp/attester.v0.ReleaseAPI/CreateReleaseAttestation -hmac-key "dotcomsecretkey"
   ```

   or run this script to store the bundle

   ```
   ./script/create-release-attest.sh
   ```
