# **Proxima Stamp Provisioning Playbook**

## Prerequisites:

- Follow this [guide](https://thehub.github.com/security/security-operations/tailscale/getting-started/) to set up Tailscale.
- Follow this [guide](https://thehub.github.com/security/security-operations/production-shell-access/shell/) to set up production shell access.

>[!TIP]
> Don't manually follow this playbook. Instead, create a new Codespace and clone needed repos by this playbook under `/workspaces` and prompt Copilot CLI with this playbook.

## Step 1. Provision Infrastructure Resources

We will first begin by provisioning the resources for CCA necessary for the new stamp. For the most part, we will either be (1) generating secrets or (2) fetching secrets from ephemeral shells. Federating these secrets will come in a later step, so don't worry about that for now. For all intents and purposes, replace <stamp> where applicable with the name of the new Proxima stamp.

- [x] **Create Vault for the Stamp**     *(The environment is the stamp)*

    Run following commands in production shell:
    ```bash
    . vault-login

    vault-secret --application <appname> --catalog-service <service_name> --environment <environment> --init

    // Example for prod-jpw-01
    vault-secret --application sweagentd --catalog-service sweagentd --environment prod-jpw-01 --init
    ```

- [x] **Provision Azure Service Principal for the Stamp**

    Reference https://github.com/github/azure-config/pull/2923 for how to provision a new service principal for the stamp. Look up the service principal ID in Azure portal and record it to be used in the next step.

- [x] **Provision sweagentd CosmosDB**
    - Use this [script](https://github.com/github/copilot-platform-api-terraform/blob/main/sweagentd-readme.md) to provision sweagentd CosmosDB resource in Azure. Reference existing stamp files as most changes for the new stamp only differ in the resource names that derive from the stamp name.
    - After merging the PR, open the Terraform app in Okta → azure-copilot → `copilot-platform-api-prod` → See Details **Confirm & Apply**. You might need to run this more than once if you experience errors such as resources being created out of order, or transient deployment errors.

- [x] **Redis Cache**

    - Redis host/server is now named in the format of `amr-sweagentd-<stamp>.<region>.redis.azure.net:10000`
    - Redis provisioning should already be handled by other teams. Consult #data-architecture to confirm the host/server endpoint.

- [x] **Configure Private Links**
  - Follow https://github.com/github/pe-automation instruction to automate private link creation for Azure resources.

-------------------------------------------------------

  ## Step 2. Update Constants
Use your production shell access to open a console targeting the proxima environment for the new stamp. From the production shell, run:
```
GH_CONSOLE=1 GITHUB_CONFIG_ROLE=console bin/console
```
Then, you can get the following values by running the below commands in the console:
- [x] GITHUB_APP_ID 
  - `::Apps::Privileged.integration(:copilot_swe_agent).id`
- [x] Set the GITHUB_APP_ID value to corresponding CAPI [stamp configuration](https://github.com/github/copilot-api/blob/dc0e4e967d21569f4b6233bc5470e93e8f60d9b2/config/kubernetes/prod-jpw-01/deployments/copilot-api.yaml#L87-L88) at `INTEGRATION_APPLICATION_IDS_COPILOT_DEVELOPER`

-------------------------------------------------------

## Step 3. Federate Secrets

- [x] **Add Stamp-Specific Aqueduct Client**
  - Follow this [guide](https://thehub.github.com/epd/engineering/products-and-services/internal/aqueduct/getting-started/#proxima) if you don't see Aqueduct secrets already in the new stamp's vault of sweagentd
``` 
// example
.aqueduct@prod-jpw-01 generate-api-key app=sweagentd
```

- [x] **Federate Vault Secrets**
  - Familiarize yourself with [vault secrets CRUD guide](https://thehub.github.com/security/security-operations/vault/configuration-variables-for-applications/#adding-and-updating-a-secret) and [secure randomness guide](https://thehub.github.com/epd/engineering/dev-practicals/secure-coding/secure-coding-general/encryption/randomness/#shell).
  - You only need to update secrets federation for secrets owned by the sweagentd service. Following are sweagentd-owned secrets that need to be generated for the new stamp and federated:
      1. `MONOLITH_TWIRP_HMAC_KEY`
      2. `APP_HMAC_KEY_COPILOT_API`
      3. `LIMITER_TWIRP_HMAC_KEY`
  - Reference https://github.com/github/secrets-federation/pull/4728 for example

-------------------------------------------------------

## Step 4. Deploy and Validate the new Stamp:
   - [x] Add the new stamp's environment [here](https://github.com/github/sweagentd/blob/main/config/moda/deployment.yaml) under `environments`.
   - [x] Add the corresponding `secrets.yml` for the new stamp (reference existing stamps for example)
   - [x] Deploy using `.deploy <PR> in <stamp> --ignore-required-pipelines` and verify the deployment works.

-------------------------------------------------------

## Step 5. Manual Validation

Run through the following workflows and ensure that they function as desired:
- [x] mission control and agent panel UI
- [x] issue assignment flow
- [x] first-party MCP tools
- [x] third-party agents (Codex, Claude)
- [x] ... more as we keep building
