# Azure

Documentation on how to work with Azure for the TMA.

## Logging In

1. Browse to [Azure portal](https://portal.azure.com)
1. When presented with a login screen, use your *GitHub Azure* login: `<your-handle>@githubazure.com`


For more information around logging in, see [additional login documentation](https://github.com/github/azure/blob/main/docs/login_to_azure.md).

## Finding TMA Resources

Azure resources are associated with specific subscriptions. All TMA resources 
can be found by filtering by either the staging or production subscriptions below.

| Environment | Subscription Name | Subscription ID |
| -----------  | ----------------- | -------------- |
| Staging | GitHub - NonProd - Supply Chain - Package Security | a0231bbd-fed8-4abc-bc8d-dc92d3e358bf |

## CLI

You can also interact with Azure resources with the Azure CLI.

You will need to use Azure JIT access:

In your DM with Hubot, you can list the Azure subscription roles you can JIT into with:

`.jit for <your handle>`

You can then JIT into a specific role with:
`.jit me to <subscription-role> in azure because <your reason here>`

You can run `az logout` and `az login` after JITing to make sure the CLI token matches the JIT role.

## Microsoft Azure Status & Incidents

The Azure public status page is available at [status.azure.com](https://status.azure.com/). You can look for recent status updates on the [Azure status history page](https://azure.status.microsoft/en-us/status/history/).

There can be some Azure incidents that do not make the public status page but can be found on the internal Microsoft incident management portal. You can access the portal with your Microsoft account and search for recent Azure incidents to see if any might be related to your issue.

To access the Microsoft ICM portal:

1. Browse to the [Microsoft ICM portal](https://aka.ms/icm)
1. When presented with a login screen, use your *Microsoft* login: `<your-microsoft-username>@microsoft.com`

# Resources

- [Azure onboarding documentation](https://github.com/github/azure/blob/main/docs/guides/getting_started.md)
