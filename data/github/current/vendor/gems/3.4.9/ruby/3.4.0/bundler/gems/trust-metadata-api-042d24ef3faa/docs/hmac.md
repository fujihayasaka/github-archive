# HMAC

TMA uses [Twirp](./twirp.md) for inter-service communication.

Github services using [Twirp APIs](https://thehub.github.com/epd/engineering/products-and-services/dotcom/features/feature-flags/twirp/) use HMAC for [Service to Service Authentication](https://thehub.github.com/epd/engineering/dev-practicals/secure-coding/secure-coding-general/service-to-service-auth/).

## Domain IDs

Each client service has a domain ID that is saved in the `attestations` table in the `domain_id` column. The domain ID is used to determine which service
created the record.

```markdown
| Domain ID | Service |
|-----------|---------|
| 1         | npm     |
| 2         | github  |
```

## Setting or Rotating the HMAC Configuration

> ⚠️ Each Twirp service should have a unique HMAC config per environment ⚠️

The HMAC configurations are stored securely in [Vault](./vault.md) as

- TMA_DOTCOM_AUTH_CONFIG
- TMA_PKG_READ_AUTH_CONFIG
- TMA_PKG_WRITE_AUTH_CONFIG

Each secret maps to an array of JSON objects that represent a specific HMAC
configuration for a given client, domain, and HMAC secret.

To set or rotate the key:

- Generate a new key with `ruby -rsecurerandom -e 'puts SecureRandom.hex(32)'`
- Access the [Vault](./vault.md) bastion and login
- Set the specific auth config vault value to include the name of the client service
  allowed to use the key, the client's domain, and the new hex key

Example:

```shell
vault-secret --application trust-metadata-api --environment staging --key TMA_PKG_READ_AUTH_CONFIG --prompt

> [
  {
    "clientId": "npm/read", # name of the client that will use the associated HMAC key
    "domain": "npm", # domain of the client. For example, the uploading-worker and npm/read clients are in the npm domain
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
`trust-metadata-api` vault under the name `TMA_DOTCOM_HMAC_KEY`. Unlike the
`TMA_DOTCOM_AUTH_CONFIG` entry described above, this value of this vault entry
should be just the HMAC key. This value is used exclusively for syncing to the
`github` vault.

The `TRUST_METADATA_HMAC_KEY` key in the `github` vault has been configured in the
[secrets-federation](https://github.com/github/secrets-federation/blob/31b7e6ed01c6a03217aa33a22f3e208993b06cab/config/federation/federation.yaml#L1595-L1604) project and can be
synced directly from the `TMA_DOTCOM_HMAC_KEY` value in the `trust-metadata-api` vault.
To sync the value, go to the `#secrets-federation` Slack channel and issue the following
command:

```shell
.secrets-federation federate trust-metadata-hmac-key
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

#### Example (status endpoint)

```shell
go run script/body-hmac-request.go -request-url "https://trust-metadata-api-staging.githubapp.com/twirp/github.trust_metadata_api.TrustMetadataAPI/Status" -request-body "{}" -request-client-name "client-name" -hmac-key "mysecretkey"
# returns {"state":"OK","commit":"871bbef"}
```

#### Example (create endpoint)

```shell
bundle=$(<testing/data/sigstoreBundle.json)
go run script/body-hmac-request -request-body '{"purl": "pkg:npm/foo/bar@12.3.1", "bundle":'"$bundle"'}' -request-url "https://trust-metadata-api-staging.githubapp.com/twirp/github.trust_metadata_api.TrustMetadataAPI/CreateAttestationByPurl"
-request-client-name "client-name" -hmac-key "mysecretkey"
```
