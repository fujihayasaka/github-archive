# HMAC

Attester uses [Twirp](./twirp.md) for inter-service communication.

GitHub services using [Twirp APIs](https://thehub.github.com/epd/engineering/products-and-services/dotcom/features/feature-flags/twirp/) use HMAC for [Service to Service Authentication](https://thehub.github.com/epd/engineering/dev-practicals/secure-coding/secure-coding-general/service-to-service-auth/).

## Setting or Rotating the HMAC Configuration

The HMAC configurations are stored securely in [Vault](./vault.md) as

- ATTESTER_RELEASE_HMAC_KEY

Each secret maps to an array of JSON objects that represent a specific HMAC
configuration for a given client, domain, and HMAC secret.

Example: `dotcomsecretkey`

To set or rotate the key:

- Generate a new key with `ruby -rsecurerandom -e 'puts SecureRandom.hex(32)'`
- Access the [Vault](./vault.md) bastion and login
- Set the specific auth config vault value to include the name of the client service
  allowed to use the key, the client's domain, and the new hex key

Example:

```shell
vault-secret --application attester --environment staging --key ATTESTER_RELEASE_HMAC_KEY --prompt

> [
  {
    "clientId": "dotcom", # name of the client that will use the associated HMAC key
    "domain": "github", # domain of the client. For example, the uploading-worker and npm/read clients are in the npm domain
    "keys": [
      "mysecret" # list of HMAC secrets this client can use with a specific Twirp service
    ]
  }
]
```

Note that `keys` is an array of strings and can accommodate multiple key values.
This is useful in situations where you may need to rotate a key without service
downtime. You can add the new key to the list, update the client with the new
key and then come back and remove the old key after the client has been updated.

### dotcom

To update dotcom with a new HMAC key, first add the new HMAC key to the
`attester` vault under the name `ATTESTER_RELEASE_HMAC_KEY`.

The `ATTESTER_HMAC_KEY` key in the `github` vault has been configured in the
[secrets-federation](https://github.com/github/secrets-federation/blob/aaf1add38dae94c1db1ccd5040dbf6a3b61e8b8c/config/federation/attester/production/federation.yaml) project and can be
synced directly from the `ATTESTER_RELEASE_HMAC_KEY` value in the `attester` vault.
To sync the value, go to the `#secrets-federation` Slack channel and issue the following
command:

```shell
.secrets-federation federate attester-hmac-key
```

## Making HMAC-authenticated requests

Make a request by computing the HMAC-SHA256 over the request's body and setting the header `Request-Body-HMAC` to the hex-encoded output of the HMAC.

Algorithm summary:

1. Get the request body
1. Compute HMAC-256 of the request body over the secret

### body-hmac-request

Use `script/body-hmac-request.go` to make a request to one of the Twirp services
using body HMAC. This script will compute the header for you. You need to provide
the request URL, client domain, HMAC secret, and request body to the script.

To use the script, get the HMAC key and associated domain for the service you
want to make a request to from [Vault](./vault.md).

#### Example

```shell

go run script/body-hmac-request.go  -request-body '{"name": "foo"}' -request-url http://localhost:8338/twirp/github.attester.HelloWorldAPI/HelloName -request-client-name "dotcom" -hmac-key "dotcomsecretkey"

./bin/twirp-test hello me --url https://attester-staging.service.iad.github.net

# returns {"message":"Hello, foo!"}
```
