# Vault

IMS uses [Hashicorp Vault](https://thehub.github.com/security/security-operations/vault/) to store and share secrets. Learn more about accessing and updating vault in [Configure vault with secrets for a new application](https://thehub.github.com/security/security-operations/vault/configuration-variables-for-applications/).

IMS vault has 2 environments: `lab`, `production`.

```bash
$ vault-secret --application hosted-compute-ims --environment production
```

## Vault secrets

- Azure SPN secrets to access Azure Subscriptions in `githubazure` tenant. These secrets are rotated automatically.
    - `SPN_HOSTED_COMPUTE_IMS`
    - `SPN_HOSTED_COMPUTE_IMS_CLIENT_ID`
    - `SPN_HOSTED_COMPUTE_IMS_TENANT_ID`
- MySQL secrets to access Vitess MySQL in GH Database Cluster. These secrets are copied from https://professorx.githubapp.com
    - `MYSQL_HOST`
    - `MYSQL_PORT`
    - `MYSQL_DATABASE_NAME`
    - `MYSQL_USER`
    - `MYSQL_PASSWORD`
    - `MYSQL_READ_ONLY_USER`
    - `MYSQL_READ_ONLY_PASSWORD`
- Aqueduct secrets. Learn more about rotating aqueduct secrets in [Aqueduct - Set up auth](https://thehub.github.com/epd/engineering/products-and-services/internal/aqueduct/getting-started/#step-2-set-up-auth)
    - `AQUEDUCT_API_KEY`
    - `AQUEDUCT_API_KEY_VERSION`
- Secrets to call IMS API from dotcom. These secrets should be rotated manually.
    - `HOSTED_COMPUTE_IMS_HMAC_KEY` - used by dotcom to make API call.
    - `HOSTED_COMPUTE_IMS_HMAC_VERIFY_KEYS` - used by IMS to validate API call. Support multiple keys separated by spaces.
- Secrets to call dotcom internal twirp API from IMS. These secrets should be rotated manually.
    - `DOTCOM_INTERNAL_TWIRP_HMAC_KEY` - used by IMS to make API call to dotcom.
    - `DOTCOM_INTERNAL_TWIRP_HMAC_VERIFY_KEYS` - used by dotcom to validate API call from IMS. Support multiple keys separated by spaces.
- Secrets to call dotcom internal API from image deployment pipelines
    - `DOTCOM_INTERNAL_TWIRP_CURATED_IMAGE_DEPLOYMENT_HMAC_VERIFY_KEYS` - used by dotcom to validate API call from [image deployment pipeline](https://dev.azure.com/mseng/AzDevNext.Deploy/_git/AzDevNext.Deploy?path=/templates/jobs/ims-deployment-job.yml). This secret is stored in [Azure DevOps Variable Group](https://dev.azure.com/mseng/AzDevNext.Deploy/_library?itemType=VariableGroups&view=VariableGroupView&variableGroupId=571&path=Compute.ImageManagementService) and should be updated manually.

## Share secrets with other applications

In some cases, IMS needs to share secrets with other applications. For example, IMS has a pair of secrets:
- `HOSTED_COMPUTE_IMS_HMAC_KEY` - is used by dotcom to make API call to IMS. This secret should be available for dotcom.
- `HOSTED_COMPUTE_IMS_HMAC_VERIFY_KEYS` - is used by IMS to validate API calls from dotcom.

Synchronization of secrets between vaults is performed by [secrets-federation](https://github.com/github/secrets-federation). It automatically copies and sync secrets between vaults based on defined rules.  
Secret federation process can be triggered manually via `.secrets-federation federate`.  
Rules for IMS can be found in https://github.com/github/secrets-federation/tree/main/config/federation/hosted-compute-ims

## Rotating HMAC secrets

HMAC secrets are always a pair of secrets:
- source - used to make API call. Usually, secret name ends with `*_HMAC_KEY` (for example, `HOSTED_COMPUTE_IMS_HMAC_KEY`)
- target - used to validate API call. Usually, secret name ends with `*_HMAC_VERIFY_KEYS` (for example, `HOSTED_COMPUTE_IMS_HMAC_VERIFY_KEYS`). Target secret always supports multiple keys separated by spaces.

Steps to rotate HMAC secrets:
1. Generate a new secret
    - Recommended way: `ruby -rsecurerandom -e 'puts SecureRandom.hex(32)'`
2. Update target secret (`HOSTED_COMPUTE_IMS_HMAC_VERIFY_KEYS`) to append a new HMAC key
    - Get old secret: `vault-secret --application hosted_compute_ims --environment production --key HOSTED_COMPUTE_IMS_HMAC_VERIFY_KEYS`
    - Update secret: `vault-secret --application hosted_compute_ims --environment production --key HOSTED_COMPUTE_IMS_HMAC_VERIFY_KEYS --prompt` and set value as `"<old_secret> <new_secret>"`
    - Make sure that new secret is federated to vault of target application
    - Re-deploy target application to consume new secret from Vault
    - At this point, IMS should accept API calls using both old or new secret
3. Update source secret to set a new HMAC key:
    - `vault-secret --application hosted_compute_ims --environment production --key HOSTED_COMPUTE_IMS_HMAC_KEY --prompt` and provide a new secret: `"<new_secret>"`
    - Make sure that new secret is federated to vault of source application
    - Re-deploy source application to use new secret from Vault
    - At this point, dotcom should start using a new secret to access IMS
4. Update target secret to delete old HMAC key
    - `vault-secret --application hosted_compute_ims --environment production --key HOSTED_COMPUTE_IMS_HMAC_VERIFY_KEYS --prompt` and set value as `"<new_secret>"`
