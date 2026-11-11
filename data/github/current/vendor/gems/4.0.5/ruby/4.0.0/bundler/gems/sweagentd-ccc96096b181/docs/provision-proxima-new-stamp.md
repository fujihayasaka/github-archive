# **Proxima Stamp Provisioning Playbook**

## Prerequisites:

- Follow this [guide](https://thehub.github.com/security/security-operations/tailscale/getting-started/) to set up Tailscale.
- Follow this [guide](https://thehub.github.com/security/security-operations/production-shell-access/shell/) to get onboarded to using ephemeral shells.

## Step 1. Provision Resources

We will first begin by provisioning the resources for CCA necessary for the new stamp. For the most part, we will either be (1) generating secrets or (2) fetching secrets from ephemeral shells. Federating these secrets will come in a later step, so don't worry about that for now. For all intents and purposes, replace <stamp> where applicable with the name of the new Proxima stamp.

- [x] **Create Vault for the Stamp**     *(The environment is the stamp)*
    ```bash
    vault-secret --application <appname> --catalog-service <service_name> --environment <environment> --init

    // Example for prod-jpw-01
    vault-secret --application sweagentd --catalog-service sweagentd --environment prod-jpw-01 --init
    ```

- [x] **Provision sweagentd CosmosDB**
    - Use this [script]( https://github.com/github/copilot-platform-api-terraform/blob/main/sweagentd-readme.md) to provision sweagentd CosmosDB
    - Verify that the below changes have been made to your stamp's file:
      - [Sweagentd, Jobs, Assignments, Logs](https://github.com/github/copilot-platform-api-terraform/blame/main/resources/proxima_jpw_01.tf#L73-L237)    
      - [Logs blob store](https://github.com/github/copilot-platform-api-terraform/blob/main/resources/proxima_jpw_01.tf#L374-L406)
      - [Cosmos DB for sessions](https://github.com/github/copilot-platform-api-terraform/blob/main/resources/proxima_jpw_01.tf#L424-L479)
      - [Role assignment for SPN, Container for Cosmos DB](https://github.com/github/copilot-platform-api-terraform/blob/main/resources/proxima_jpw_01.tf#L481-L506)
    - You will need to locate the principal ID in Azure and update the value accordingly.

- [x] **Apply Terraform**
  - After merging, open the Terraform app in Okta → azure-copilot → `copilot-platform-api-prod` → See Details **Confirm & Apply**
  - Note: You might need to run this more than once if you experience an error in which some resources are created and others are not. In my experience, that usually resolves things.

- [x] **Configure Private Links**
  - Follow these [sweagentd CosmosDB private link changes](https://github.com/github/sites/commit/51d71c48e117baf9b2fbb8f38ac2ca89caeefd5d) as a reference to create a PR to generate a new private link for the stamp.
  - Go to [#private-link-support ](https://github-grid.enterprise.slack.com/archives/C08LYFQ2Q90) channel, ask for approval
  - Someone will run the Terraform plan for you, and send a screenshot of the output. Review the output to see if it looks reasonable.
  - Once approval is received, check the box on the auto-generated PR comment as it's merging to confirm merge.
  - Go to Okta -> Azure Prod JIT -> Sign out and sign back in -> Go to Azure -> Resource Groups -> `sweagentd-cosmos-db-<stamp>` -> Click into the database resource -> Networking -> Do not click the connection endpoint name (link), but rather **HOVER** around it and you will see it turn gray. Click the tab while it's being hovered, then **manually approve** the private link on the Networking tab of the resource.

<img width="1912" height="891" alt="Image" src="https://github.com/user-attachments/assets/f68912a3-1561-4465-a96c-30dda7c0c710" />

- [x] **Add Stamp-Specific Aqueduct Client**
  - Follow this [guide.](https://thehub.github.com/epd/engineering/products-and-services/internal/aqueduct/getting-started/#proxima)
``` 
// example
.aqueduct@prod-jpw-01 generate-api-key app=sweagentd
```

- [x] **Fetch & Add Vault Values & Local Secrets**
  - Reference this [Vault manual secret add guide](https://thehub.github.com/security/security-operations/vault/configuration-variables-for-applications/#adding-and-updating-a-secret). You will now need to get the values/secrets for the below and then add them to the vault for this stamp environment:
    - [x] Generate the following using the [secure randomness guide](https://thehub.github.com/epd/engineering/dev-practicals/secure-coding/secure-coding-general/encryption/randomness/#shell):
      - `LIMITER_TWIRP_HMAC_KEY`
      - `MONOLITH_TWIRP_HMAC_KEY` 
    - [x] Go to Okta -> Azure Prod JIT -> Sign out and sign back in -> Go to Azure -> Resource Groups -> `sweagentd-rg-<stamp>-cosmos-rg` -> `sweagentd-cosmos-db-<stamp>`. Go to Settings -> Keys -> Copy the PRIMARY CONNECTION STRING value, that will be the value for the `AZURE_COSMOSDB_CONNECTION_STRING` key.

<img width="1466" height="710" alt="Image" src="https://github.com/user-attachments/assets/909a9930-0edf-4fd9-a1a7-4c30929ad623" />

- [x] SSH into shell and [copy](https://thehub.github.com/security/security-operations/vault/configuration-variables-for-applications/#viewing-a-secret) the following values from sweagentd prod environment:
   - `GITHUB_APP_CLIENT_ID`
   - `GITHUB_APP_CLIENT_SECRET`
- [x] Assuming you have the prerequisites at the top of the playbook, you need to:
  - Navigate to the [#shell-ops channel](https://github-grid.enterprise.slack.com/archives/C072FBPJDS9)
  - Run the following: 
    - ```.jit me to kubelogin in tailscale for 3h because using ephemeral shells```
    - ```.shell me to kubectl for 3h because ephemeral shell```
      - Connect to the kubectl ephemeral shell
      - Run `. vault-login`
      - Run `gh-kubeconfig`
      - Run `kubectl config use proxima-3-prod-<stamp>-az3`
      - Run `k9s -n github-prod-jpw-01`, which will launch the k9s CLI.
        - Use the '/' key to search for "unicorn", which will show unicorn pods for the prod proxima stamp.
        - Press the 'enter' key on a unicorn pod, which will then show a list of containers for this unicorn pod.
        - Navigate down using arrow keys to the unicorn container in the unicorn pod, then press the 's' key to open the shell.
        - Run `bin/rake proxima:app_sync:add_public_key['<copilot_swe_agent>']`. This will be the value for the `GITHUB_APP_PRIVATE_KEY`.
- [x] Get `CLIENT_SECRETS_COPILOT_DEVELOPER` from another Proxima env vault (these are the same across envs) and add to the vault by following the above guide.
- [x] Create a new HMAC key for `COPILOT_PLATFORM_API_AND_COPILOT_DEVELOPER_HMAC_SECRET`


- [x] **Proxima Stamp-Specific SPN** *(Nice-to-have)*
  - Create a spn entry similar to this [reference PR](https://github.com/github/azure-config/pull/624/files)
  - This is not a necessary step, but is a nice to have.


-------------------------------------------------------
  ## Step 2. Update Constants
Run a production console targeting the proxima environment for the new stamp. To target this, follow the same process above with the ephemeral shell. Once you're in the unicorn container, you can access the console with:
```
GH_CONSOLE=1 GITHUB_CONFIG_ROLE=console bin/console
```
Then, you can get the following values by running the below commands in the console:
- [x] GITHUB_APP_ID 
  - `::Apps::Privileged.integration(:copilot_swe_agent).id`
- [x] GitHub Bot ID (which is also repeated in the GITHUB_COMMIT_EMAIL) 
  - `::Apps::Privileged.integration(:copilot_swe_agent).bot_id`
- [x] GITHUB_BOT_LOGIN (which is also repeated in the GITHUB_COMMIT_LOGIN)
  - `::Apps::Privileged.integration(:copilot_swe_agent).bot.login`
- [x] Using the values above, you must propagate it to 2 places:
   - [x] Add to our [proxima stamp specific configuration](https://github.com/github/sweagentd/blob/main/config/moda/configuration/prod-ae-01/env.yaml).
   - [x] Update CAPI's proxima [stamp specific configuration](https://github.com/github/copilot-api/blob/main/config/kubernetes/staff-wus2-01/deployments/copilot-api.yaml#L89)

-------------------------------------------------------

## Step 3. Federate Secrets
All secret federation here will be done in `github/secrets-federation`, so it is recommended that you combine all of these federations into a singular PR in order to minimize number of review requests that you need.
   - [x] [Federate](https://github.com/github/secrets-federation/pull/2958/files) the Internal API HMAC key.
   - [x] Above, we provisioned an aqueduct client, [now we federate](https://github.com/github/secrets-federation/pull/2959#top) those values.
   - [x] [Federate `CAPI_HMAC_KEY`](https://github.com/github/secrets-federation/pull/2961)
   - [x] [Federate our HMAC key to monolith](https://github.com/github/secrets-federation/pull/2946)
   - [ ] Add your new stamp to these [github/github authorization secrets](https://github.com/github/secrets-federation/blob/main/config/federation/github/production/authorization.yml)

-------------------------------------------------------

## Step 4. Deploy and validate the stamp:
   - [x] [Add the new stamp's environment here](https://github.com/github/sweagentd/blob/main/config/moda/deployment.yaml#L6)
   - [x] Add the resource [config](https://github.com/github/sweagentd/pull/4687) to the deployment.yaml as well.
   - [x] Add the corresponding secrets.yml [file](https://github.com/github/sweagentd/blob/main/config/moda/secrets/prod-weu-01/secrets.yaml) that defines which secrets the environment uses
   - [x] Deploy using `.deploy <PR> in <stamp> --ignore-required-pipelines` and verify the deployment works.
 
<img width="383" height="577" alt="Image" src="https://github.com/user-attachments/assets/b493b47d-4226-4630-a65d-5c33bdc51545" />

   - [x] These feature flags should be automatically be enabled for the new stamp, but just to be sure you should sanity check that these flags are enabled for the stamp:
      - [x] copilot_api_sweagent
      - [x] sweagentd_firewall_ui
      - [x] copilot_api_agent_sessions
      - [x] copilot_api_agentproxy_token_descryption
      - [x] copilot_swe_agent_feedback
      - [x] copilot_swe_agent_gzip_problem_statement
      - [x] sweagentd_firewall_use_ruleset_allow_list
      - [x] coding_agent_in_proxima

-------------------------------------------------------

## Step 5. Manual validation in the UI

Run through the following workflows and ensure that they function as desired:
- [x] 'copilot/agents' UI/view
- [x] CCA Issue Assignment & PR creation
- [x] 1st party tools via MCP
- [x] 'View Sessions' and session logs
- [ ] Mid-session Steering
