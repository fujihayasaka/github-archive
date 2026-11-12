## Dogfooding with sweagent-aip models

NOTE 6/25/2025: `sweagent-aip` is not supported for production as AIP endpoint has been deleted. This will be enabled once a new endpoint will be made available for dogfooding.

`sweagent-aip` is a private endpoint from the Azure AI Platform team. This is an internal only dogfooding endpoint.

To enable your repo/org to dogfood with the endpoint:

1. Set up a managed identity that has access SWE Agent Dogfooder Entitlement via [CoreIdentity](https://coreidentity.microsoft.com/manage/Entitlement/entitlement/sweagentdogf-5nbb). You can onboard up to 10 repos with one Managed identity.

2. Establish FIC trust relationship with each repo you want to enable for dogfooding with `sweagent-aip`. You can this in the azure portal by going to the MI, Settings -> Federated credentials and doing Add Credential. The scenario should be "GitHub Actions Deploying Azure Resources". Put in the correct org and repository, for entity pick "environment" and for the value use "copilot". The name under credential details does not matter, pick anything. See [how](https://learn.microsoft.com/en-us/entra/workload-id/workload-identity-federation-create-trust-user-assigned-managed-identity?pivots=identity-wif-mi-methods-azp#configure-a-federated-identity-credential-on-a-user-assigned-managed-identity)

3. Add a `.github/workflows/copilot-setup-steps.yaml` file in the repo with the following steps in the file:

```yaml
name: "Copilot Setup Steps"

on: workflow_dispatch

jobs:
    copilot-setup-steps:
        runs-on: ubuntu-latest
        permissions:
            id-token: write
            contents: read
        steps:
            - name: Azure Login
              uses: azure/login@a65d910e8af852a8061c627c456678983e180302 #v2.2.0
              with:
                  client-id: "<MI-client-id>"
                  tenant-id: "<MI-tenant-id>"
                  subscription-id: "<MI-subscription-id>"
```

4. To enable endpoint communication you need to add the following `login.microsoftonline.com,https://swe-agent-relay.eastus2.inference.ml.azure.com` to your `COPILOT_AGENT_FIREWALL_ALLOW_LIST_ADDITIONS`. To do that, set an actions level variable on the repository. See [how here](https://docs.github.com/en/actions/writing-workflows/choosing-what-your-workflow-does/store-information-in-variables#creating-configuration-variables-for-a-repository).

That's it!

See `docs/models.md` on supported models via `sweagent-aip` client and how to use them.
