# HMAC Key Rotation

Each client of TMA uses a distinct [HMAC key](../hmac.md) in order to authenticate with the service.

In the event of a security breach, it may be necessary to rotate an HMAC key. To ensure that we can update HMAC keys without downtime, TMA accepts a list of valid keys -- any of which can be used to authenticate a request.

The first step in the key rotation is to generate a new key value:

```shell
ruby -rsecurerandom -e 'puts SecureRandom.hex(32)'
```

From there, you'll need to access the [Vault](https://github.com/github/trust-metadata-api/blob/main/docs/vault.md) bastion and login.

The remaining steps are client-specific and described in the sections below.

## dotcom

Add the new HMAC key to `keys` list under `TMA_DOTCOM_AUTH_CONFIG`. Start by dumping the current
value of the `TMA_DOTCOM_AUTH_CONFIG` vault entry:

```shell
vault-secret --application trust-metadata-api --key TMA_DOTCOM_AUTH_CONFIG
```

Update the entry by adding the new key value to the list IN ADDITION TO the existing key vaule:

```shell
vault-secret --application trust-metadata-api --environment production --key TMA_DOTCOM_AUTH_CONFIG --prompt

> [
  {
    "clientName": "dotcom",
    "domain": "github",
    "keys": [ "oldsecret", "newsecret" ]
  }
]
```

Also, update the `TMA_DOTCOM_HMAC_KEY` entry with the new HMAC key -- this entry should contain JUST the raw HMAC key, NOT the JSON structure shown above:

```shell
vault-secret --application trust-metadata-api --environment production --key TMA_DOTCOM_HMAC_KEY --prompt

> newsecret
```

The value of the `TMA_DOTCOM_HMAC_KEY` entry is the one which is used to [synchronize](https://github.com/github/secrets-federation/blob/31b7e6ed01c6a03217aa33a22f3e208993b06cab/config/federation/federation.yaml#L1595-L1604) the value into the github vault.

With the new HMAC key in place, first trigger a deployment of TMA in order to pick-up the new vault configuration. From the `#package-security-ops` channel, run the following:

```
.deploy trust-metadata-api to production
```

To synchronize the new key value to the github vault, go to the `#secrets-federation` Slack channel and run the following:

```
.secrets-federation federate trust-metadata-hmac-key
```

or, alternatively:

```
.secrets-federation federate
```

In order for dotcom to pick-up the new key vaule, you need to trigger a deployment. You can either wait for whatever deployment may already be in progress or initiate a new deployment by opening a PR for `github/github` and getting it into the merge queue.

Once dotcom has been deployed, you can go back and remove the old HMAC key from the TMA configuration:

```shell
vault-secret --application trust-metadata-api --environment production --key TMA_DOTCOM_AUTH_CONFIG --prompt

> [
  {
    "clientName": "dotcom",
    "domain": "github",
    "keys": [ "newsecret" ]
  }
]
```

Complete the key rotation by triggering a final TMA deployment in the `#package-security-ops` channel:

```
.deploy trust-metadata-api to production
```

## npm (wubwub)

Add the new HMAC key to `keys` list under `TMA_PKG_READ_AUTH_CONFIG`. Start by dumping the current
value of the `TMA_PKG_READ_AUTH_CONFIG` vault entry:

```shell
vault-secret --application trust-metadata-api --key TMA_PKG_READ_AUTH_CONFIG
```

Update the entry by adding the new key value to the list IN ADDITION TO the existing key vaule:

```shell
vault-secret --application trust-metadata-api --environment production --key TMA_PKG_READ_AUTH_CONFIG --prompt

> [
  {
    "clientName": "npm/read",
    "domain": "npm",
    "keys": [ "oldsecret", "newsecret" ]
  }
]
```

With the new HMAC key in place, first trigger a deployment of TMA in order to pick-up the new vault configuration. From the `#package-security-ops` channel, run the following:

```
.deploy trust-metadata-api to production
```

The new secret will need to be added to the npm AWS Secrets Manager under the name `wubwub/tma-read-hmac-secret`. Get in touch with the npm team in the `#npm-engineering` Slack channel to get help updating this value and redeploying the wubwub service.

Once wubwub has been deployed, you can go back and remove the old HMAC key from the TMA configuration:

```shell
vault-secret --application trust-metadata-api --environment production --key TMA_PKG_READ_AUTH_CONFIG --prompt

> [
  {
    "clientName": "npm/read",
    "domain": "npm",
    "keys": [ "newsecret" ]
  }
]
```

Complete the key rotation by triggering a final TMA deployment in the `#package-security-ops` channel:

```
.deploy trust-metadata-api to production
```

## npm (uploading-worker)

Add the new HMAC key to `keys` list under `TMA_PKG_WRITE_AUTH_CONFIG`. Start by dumping the current
value of the `TMA_PKG_WRITE_AUTH_CONFIG` vault entry:

```shell
vault-secret --application trust-metadata-api --key TMA_PKG_WRITE_AUTH_CONFIG
```

Update the entry by adding the new key value to the list IN ADDITION TO the existing key vaule:

```shell
vault-secret --application trust-metadata-api --environment production --key TMA_PKG_WRITE_AUTH_CONFIG --prompt

> [
  {
    "clientName": "uploading-worker",
    "domain": "npm",
    "keys": [ "oldsecret", "newsecret" ]
  }
]
```

With the new HMAC key in place, first trigger a deployment of TMA in order to pick-up the new vault configuration. From the `#package-security-ops` channel, run the following:

```
.deploy trust-metadata-api to production
```

The new secret will need to be added to the npm AWS Secrets Manager under the name `uploading-worker/tma_create_hmac_secret`. Get in touch with the npm team in the `#npm-engineering` Slack channel to get help updating this value and redeploying the uploading-worker service.

Once uploading-worker has been deployed, you can go back and remove the old HMAC key from the TMA configuration:

```shell
vault-secret --application trust-metadata-api --environment production --key TMA_PKG_WRITE_AUTH_CONFIG --prompt

> [
  {
    "clientName": "uploading-worker",
    "domain": "npm",
    "keys": [ "newsecret" ]
  }
]
```

Complete the key rotation by triggering a final TMA deployment in the `#package-security-ops` channel:

```
.deploy trust-metadata-api to production
```
