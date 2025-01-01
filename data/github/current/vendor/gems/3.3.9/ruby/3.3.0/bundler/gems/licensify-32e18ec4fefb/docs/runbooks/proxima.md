# Proxima Runbook

Below is a step by step guide to configure Licensify in a new Proxima stamp.

## Steps

### 1. Create Terraform Workspace

- Follow the [paved path guidance on creating a new Terraform workspace](https://github.com/github/CosmosDB/blob/main/docs/deployment.md#creating-a-workspace) for the new stamp
    - This is the link to GitHub's Terraform enterprise instance: https://terraform.githubapp.com/app
    - Ensure you update the following:
        - Settings -> Execution Mode -> Remote
        - Settings -> Terraform Working Directory -> [stamp]
        - Settings -> Team Access -> Add `tfe-compute-foundation`, `tfe-licensing`, `tfe-security-ops`
        - Variables -> Add the following:
            - Select "Environment variable", Key = `TFC_VAULT_ADDR` Value = `https://vault.service.github.net:8200`
            - Select "Environment variable", Key = `TFC_VAULT_AUTH_PATH` Value = `tfe`
            - Select "Environment variable", Key = `TFC_VAULT_PROVIDER_AUTH` Value = `true`
            - Select "Environment variable", Key =  `TFC_VAULT_RUN_ROLE` Value = `azure-licensing-default-licensing-prod`
- Once the workspace is created, setup a Codespace in [github/licensify](https://github.com/github/licensify)
- Add the new stamp to the `environment-targets` list in `.github/workflows/terraform-branch-deploy.yml`
- Add the new stamp to the `environment_targets` list in `.github/workflows/unlock-on-merge.yml`
- Merge the PR

### 2. Create Terraform Resources

See [adding a new stamp](https://github.com/github/licensify/blob/main/docs/cosmosdb_and_proxima.md#adding-a-new-stamp) for more details.

- Setup a Codespace in [github/licensify](https://github.com/github/licensify)
- In `config/terraform` create a new folder for the new stamp and copy the contents of the [`prod-sdc-01`](https://github.com/github/licensify/tree/main/config/terraform/prod-sdc-01) folder
    - Do not copy over the `.terraform.lock.hcl`
- Update the `main.tf` with the new stamp's info
    - Replace all occurrences of `prod-sdc-01` with the new stamp
    - Replace all occurrences of `prodsdc01` with the new stamp
    - Replace the `location` with the stamps location
        - The location for your stamp can be found in https://github.com/github/proxima/blob/main/docs/proxima-azure-datacenters.md#data-center-locations
- Add a primary and secondary region mapping to `config/terraform/application/constants.tf` for the new stamp
    - Region mappings for your stamp can be found in https://github.com/github/proxima/blob/main/docs/proxima-azure-datacenters.md#proxima-stamp-to-region-mapping
- Run `terraform init` in the stamps Terraform directory
    - This should create a new `.terraform.lock.hcl` file
- Create a PR and run terraform noop deployments:
    - `.noop [stamp]`
- Request a review from the licensing team if noop deployments are successful
- Run Terraform deploy command:
    - `.deploy [stamp]`
- Verify new resources in Azure portal
- Merge the PR

### 3. Create Vault Environment

Create a new Vault environment for the new stamp.

- SSH to Vault bastion
    - `ssh [github-handle]@vault-bastion.githubapp.com`
- Login to Vault
    - `. vault-login`
- Create a new Vault environment for the Licensify Vault application
    - `. vault-secret --application licensify --environment [stamp] --catalog-service licensify --init`
- Verify the environment was created successfully
    - `. vault-secret --application licensify --list-environments`

### 4. Configure Aqueduct

From [Aqueduct getting started](https://thehub.github.com/epd/engineering/products-and-services/internal/aqueduct/getting-started), run the following chatop in [#data-pipelines-ops](https://github-grid.enterprise.slack.com/archives/C9HSRQCDR) ([example](https://github.slack.com/archives/C9HSRQCDR/p1725993772961399)):

```
.aqueduct@[stamp] generate-api-key app=licensify-production
```

*This sets values in the `aqueduct-client-licensify-production` Vault application that we will federate to the Licensify Vault in proceeding steps.*

### 5. Manually Set Secrets

Manually set secrets that are required for the Licensify application to run.

- SSH to Vault bastion
    - `ssh [github-handle]@vault-bastion.githubapp.com`
- Login to Vault
    - `. vault-login`
- Run the following, be sure to replace `[stamp]` with the new stamp:
```
. vault-secret --application licensify --environment [stamp] --key AZURE_COSMOS_ENDPOINT -v https://licensify-[stamp].documents.azure.com:443
. vault-secret --application licensify --environment [stamp] --key HMAC_KEYS -v $(openssl rand -hex 32)
. vault-secret --application licensify --environment [stamp] --key MONOLITH_TWIRP_HMAC_KEY -v $(openssl rand -hex 32)
```
- Acquire temporary GitHub Vault access by adding yourself to https://github.com/github/entitlements/blob/master/ldap/apps/vault-secrets/read-write/github.txt
- Run the following, be sure to replace `[stamp]` with the new stamp:
```
. vault-secret --application github --environment [stamp] --key LICENSIFY_HOST -v https://licensify-[stamp].service.[stamp].github.net
```
- Set the Azure blob storage account name. If the Azure blob storage for the stamp was configured in Terraform with a `storage_account_name`, use this value, ex: `licensingprodsdc01`. If a `storage_account_name` was not provided, a [default name](https://github.com/github/terraform-azurerm-github-blob-storage/blob/5a95adf1d71d7917414b2e4750a877379e4276d9/modules/azure-blob-storage-account/main.tf#L18) is set. You should be able to go to the Azure portal (you will need to [JIT into the production licensing Azure subscription](https://github.com/github/licensing/blob/main/docs/azure-blob-storage-setup.md#accessing-storage-accounts)) and find the account name.

```
. vault-secret --application github --environment [stamp] --key LICENSING_AZURE_STORAGE_ACCOUNT_NAME -v [account_name]
```

### 6. Federate Secrets

Licensify uses [github/secrets-federation](https://github.com/github/secrets-federation) to federate secrets stored in the Licensify vault to the GitHub Vault and to share licensing GitHub vault secrets across stamps.

- Setup a Codespace in [github/secrets-federation](https://github.com/github/secrets-federation)
- Create a new folder in `config/federation/licensify` for the new stamp
- Create a `federation.yaml` file in the new folder
- Copy the contents of `config/federation/licensify/prod-weu-01/federation.yaml` into this file
    - Replace all occurrences of `prod-weu-01` with the new stamp
- In `config/federation/github/production/federation.yaml`
    - Add an entry for the new stamp to the `spn_github_licensing_prod` key
    - Add an entry for the new stamp to the `spn_github_licensing_prod_client_id` key
    - Add an entry for the new stamp to the `spn_github_licensing_prod_tenant_id` key
    - Add an entry for the new stamp to the `ENTERPRISE_USER_LICENSE_LIST_PRIVATE_KEYS` key
- Create a new folder for the stamp in `config/federation/aqueduct-client-licensify-production` and copy the contents of the Sweden `federation.yaml` into the new folder
    - Be sure to replace instances of `prod-sdc-01` with the new stamp
- Create & deploy the PR

### 7. Create SPN

Licensify uses a read-write SPN to connect to Cosmos DB. We want to create a new SPN for the new stamp.

- Setup a Codespace in [github/azure-rbac](https://github.com/github/azure-rbac)
- Create a new file in `tf/rbac` named `spn-licensify_cosmosdb_rw_[stamp_with_underscores].tf`
    - Note `stamp_with_underscores` is the stamp name with dashes replaced with underscores (e.g. `prod-weu-01` -> `prod_weu_01`)
- Copy the contents of `tf/rbac/spn-licensify_cosmosdb_rw_prod_weu_01.tf` into this file
- Replace all instances of `prod_weu_01` and `prod-weu-01` with the new stamp
- Create & deploy the PR

### 8. Setup private link for Cosmos DB

- Setup a Codespace in [github/sites](https://github.com/github/sites)
- Using https://github.com/github/sites/pull/1596 as a guide, add a new entry for your new stamp in `sites/[stamp]/private_endpoints.tf`
- Create & deploy the PR

### 9. Add DNS cache entries for private links

- Setup a Codespace in [github/puppet](https://github.com/github/puppet)
- Using https://github.com/github/puppet/pull/37735 as a guide, add a new entry for your new stamp in `hieradata/provider/gpanel/dns-cache.yaml`
- Create & deploy the PR

### 10. Deploy Licensify

- Deploy Licensify to the new stamp via chatops
    - `.deploy licensify/main to [stamp]`

## Resources

- [Creating new Vault environment](https://thehub.github.com/security/security-operations/vault/configuration-variables-for-applications/#creating-a-new-environment)
- [Adding a new Cosmos DB stamp](https://github.com/github/licensify/blob/main/docs/cosmosdb_and_proxima.md#adding-a-new-stamp)
- [Aqueduct getting started](https://thehub.github.com/epd/engineering/products-and-services/internal/aqueduct/getting-started)
- [Proxima Azure data centers](https://github.com/github/proxima/blob/main/docs/proxima-azure-datacenters.md)
