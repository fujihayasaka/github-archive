# **Proxima Stamp Provisioning Playbook**

## 1. Provision Resources

- [ ] **Create Vault for the Stamp**
  - Run:
    ```bash
    vault-secret --application <appname> --catalog-service <service_name> --environment <environment> --init
    ```
    *(The environment is the stamp)*

- [ ] **Provision sweagentd CosmosDB**
  - Reference [Proxima-specific Terraform changes](https://github.com/github/copilot-platform-api-terraform/compare/998b7f8b9f4576de4743d0d26a4dbc1f3dcf3328...fff768cd113fd389d15e0e4e611b4fe4598af6db) in `resources/proxima_staff_wus2_01.tf` which does the following:
    - [Logs blob store](https://github.com/github/copilot-platform-api-terraform/blob/998b7f8b9f4576de4743d0d26a4dbc1f3dcf3328/resources/proxima_staff_wus2_01.tf#L218C9-L218C45)
    - [Cosmos DB for sessions](https://github.com/github/copilot-platform-api-terraform/blob/998b7f8b9f4576de4743d0d26a4dbc1f3dcf3328/resources/proxima_staff_wus2_01.tf#L404)
    - [Role assignment for SPN](https://github.com/github/copilot-platform-api-terraform/blob/998b7f8b9f4576de4743d0d26a4dbc1f3dcf3328/resources/proxima_staff_wus2_01.tf#L456)
    - [Container for Cosmos DB](https://github.com/github/copilot-platform-api-terraform/blob/998b7f8b9f4576de4743d0d26a4dbc1f3dcf3328/resources/proxima_staff_wus2_01.tf#L466)

- [ ] **Apply Terraform**
  - After merging, open the Terraform app in Okta → `copilot-platform-api-prod` → **Confirm & Apply**

- [ ] **Configure Private Links**
  - Follow [sweagentd CosmosDB private link PR](https://github.com/github/sites/pull/2362/files) to create a PR to generate a new private link for the stamp.
  - Merge PR, then **manually approve** the private link on the Networking tab of the resource *(JIT into prod Azure in Okta)* You must highlight link and then click approve.

- [ ] **Add Stamp-Specific Aqueduct Client**
  - Follow the [guide](https://thehub.github.com/epd/engineering/products-and-services/internal/aqueduct/getting-started/#proxima) on how to do this.
  - Will federate these in a later step.

- [ ] **Add Vault Values & Local Secrets**
  - A lot of these secrets are federated later, but there are some manual additions required:
    - [ ] [Vault manual secret add guide](https://thehub.github.com/security/security-operations/vault/configuration-variables-for-applications/#adding-and-updating-a-secret)
    - [ ] Generate:
      - `LIMITER_TWIRP_HMAC_KEY`
      - `MONOLITH_TWIRP_HMAC_KEY` → using the [secure randomness guide](https://thehub.github.com/epd/engineering/dev-practicals/secure-coding/secure-coding-general/encryption/randomness/#shell)
    - [ ] Grab the `AZURE_COSMOSDB_CONNECTION_STRING` from the (JIT) Azure Okta tile and navigating to settings → keys and grab the `PRIMARY_CONNECTION_STRING` value.
    - [ ] SSH into shell and [copy](https://thehub.github.com/security/security-operations/vault/configuration-variables-for-applications/#viewing-a-secret) the following values from sweagentd prod environment:
      - `GITHUB_APP_CLIENT_ID`
      - `GITHUB_APP_CLIENT_SECRET`
    - [ ] Get `GITHUB_APP_PRIVATE_KEY` using these [instructions](https://thehub.github.com/epd/engineering/products-and-services/dotcom/apps/proxima/how-to-synchronize-apps-on-proxima/#what-about-my-apps-private-andor-public-keys-are-these-synchronized)
      *(Use `copilot_swe_agent` for the app alias)*
    - [ ] Get `CLIENT_SECRETS_COPILOT_DEVELOPER` from another Proxima env vault (these are the same across envs) and add to the vault.

- [ ] **Proxima Stamp-Specific SPN** *(Nice-to-have)*
  - Create a spn entry similar to this [reference PR](https://github.com/github/azure-config/pull/624/files)
  - This is not a necessary step, but is a nice to have.

  ## 2. Update Constants
- [ ] Run a production console targeting the proxima environment in question. Our app should already be replicated out to all proxima environments. You can do this by sshing into the stamp env (`ssh -A shell.service.STAMP.github.net` and running `gh-console`.
- [ ] Get the GITHUB_APP_ID by doing:
  - `::Apps::Privileged.integration(:copilot_swe_agent).id`
- [ ] Get the GitHub Bot ID (which is used in the GITHUB_COMMIT_EMAIL) by doing:
  - `::Apps::Privileged.integration(:copilot_swe_agent).bot_id`
- [ ] Get the GITHUB_BOT_LOGIN by doing:
  - `::Apps::Privileged.integration(:copilot_swe_agent).bot.login`
- [ ] Take the previously generated App ID above and propagate it to two places:
   - [ ] Add to our proxima stamp specific configuration like [so](https://github.com/github/sweagentd/blob/main/config/moda/configuration/prod-ae-01/env.yaml).
   - [ ] Update CAPI's proxima [stamp specific configuration](https://github.com/github/copilot-api/blob/main/config/kubernetes/staff-wus2-01/deployments/copilot-api.yaml#L89)
- [ ] Also, add sweagentd's URL [to CAPI's matching proxima deployment](https://github.com/github/copilot-api/pull/17700/files)

## 3. Federate Secrets
You should do all of these federations in one PR in order to minimize number of review requests that you need.
   - [ ]  [Federate](https://github.com/github/secrets-federation/pull/2958/files) the Internal API HMAC key.
   - [ ] You already provisioned an aqueduct client in a previous step, [now federate](https://github.com/github/secrets-federation/pull/2959#top) those values.
   - [ ] [Federate `CAPI_HMAC_KEY`](https://github.com/github/secrets-federation/pull/2961)
   - [ ] [Federate our two HMAC keys to limiter / monolith](https://github.com/github/secrets-federation/pull/2946)

## 4. Deploy and validate the stamp:
   - [ ] [Add the new stamp's environment here](https://github.com/github/sweagentd/blob/main/config/moda/deployment.yaml#L6)
   - [ ] Add the resource [config](https://github.com/github/sweagentd/pull/4687) to the deployment.yaml as well.
   - [ ] Add the corresponding secrets.yml [file](https://github.com/github/sweagentd/blob/main/config/moda/secrets/prod-weu-01/secrets.yaml) that defines which secrets the environment uses
   - [ ] Deploy using `.deploy <PR> in <stamp> --ignore-required-pipelines` and verify the deployment works.
   - [ ] Enable these feature flags globally:
      - [ ] copilot_swe_agent_job_secrets_provider_skip_codeload_in_proxima
      - [ ] copilot_api_sweagent
      - [ ] sweagentd_firewall_ui
      - [ ] copilot_api_agent_sessions
      - [ ] copilot_api_agentproxy_token_descryption
      - [ ] copilot_swe_agent_feedback
      - [ ] copilot_swe_agent_gzip_problem_statement
      - [ ] sweagentd_firewall_use_ruleset_allow_list
      - [ ] agent_session_send_tenant_headers
      - [ ] copilot_swe_agent_job_secrets_provider_skip_codeload_in_proxima
      - [ ] sweagentd_blackbird_initial_search
      - [ ] copilot_on_proxima
      - [ ] sweagentd_proxima_tenant_resolution_in_config
  - [ ] Enable this flag at the user, repo, org and business level (so should you have at least 4 entries)
    - [ ] coding_agent_in_proxima

## 5. Manual validation in the UI
- [ ] Ensure the 'copilot/agents' UI works
- [ ] Assign copilot to an issue and the action kicks off and PR is created as expected
- [ ] Verify that 1st party tools via MCP works
- [ ] Ensure the `View Sessions` button shows up and you can view Session logs as expected
