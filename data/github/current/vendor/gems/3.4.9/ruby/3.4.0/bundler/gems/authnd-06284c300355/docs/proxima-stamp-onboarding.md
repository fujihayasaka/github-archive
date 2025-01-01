# Proxima stamp onboarding guide for authnd

This guide is meant to list all of the steps required for onboarding `authnd` to a new Proxima stamp.

### 1. Vault setup

The following steps need to be completed on the prodshell console after performing `. vault-login`.

1. Initialize the Vault environment and automatically populate secrets where possible:

```bash
export STAMP=<FILL-THIS-IN>

# initialize vault environment for stamp
vault-secret -a authnd -e $STAMP --init --catalog-service github/authnd

# copies a vault secret from the github app to the authnd app for the provided stamp
copy_secret() {
    FROM_KEY=$1
    TO_KEY=$2
    echo ">>> copying github:$FROM_KEY to authnd:$TO_KEY..."
    vault-secret -a github -e $STAMP -k $FROM_KEY | xargs -n1 -I{} vault-secret -a authnd -e $STAMP -k $TO_KEY -v {}
}

# copy secrets from `github` vault
VAULT_KEYS=(
  FAILBOT_HAYSTACK_URL
)
for KEY in "${VAULT_KEYS[@]}"
do
    copy_secret $KEY $KEY
done

# OTEL configuration
vault-secret -a authnd -e $STAMP -k OTEL_EXPORTER_OTLP_TRACES_ENDPOINT -v http://otelcol-mesh.otelcol-production.svc.cluster.local:14318/v1/traces

# authnd URL for gh/gh
vault-secret -a github -e $STAMP -k AUTHND_SERVICE_URL -v "https://authnd.service.$STAMP.github.net"
```

2. Create a secrets-federation PR to federate MySQL credentials to the authnd Vault space (e.g. https://github.com/github/secrets-federation/pull/1517).

[^1]: Use the `--prompt` flag on the `vault secret` CLI to avoid the secrets leaking into the shared bash history.

#### 1.1 Configure federated values into the new vault

Any federated values to the authnd vault need to be added to the config specific to the new stamp. Right now this is only the hubot chatop public key, which has [this example PR](https://github.com/github/secrets-federation/pull/301)

### 2. Pipeline setup & validation

1. Once CI is green you should be able to deploy with `.deploy <PR> to <STAMP>`.
2. You should be able to find the stamp Okta staff tenant in the [Proxima tenant docs](https://github.com/github/proxima/blob/main/docs/tenants.md).
3. Manually validate basic functionality is working (e.g. PATsv2 CRUD).[^2]
4. Ship your PR and :tada:!

[^2]: Note that the `AUTHND_SERVICE_URL` change in the github Vault may require a Dotcom deploy to complete before taking effect.
