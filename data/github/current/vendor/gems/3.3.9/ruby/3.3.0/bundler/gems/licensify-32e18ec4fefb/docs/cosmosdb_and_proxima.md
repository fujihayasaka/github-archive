# Cosmos DB and Proxima
The purpose of this doc is to detail the steps taken to establish a presence in Proxima, and the steps necessary to expand that presence to a new stamp.

## Base Requirements
### Azure SPN
In order to interact with Azure you need an Azure Subscription aka Azure Service Principal (SPN). The creation process is outlined by the [GitHub Azure team](https://github.com/github/azure/blob/main/docs/guides/getting_started.md#step-3---create-an-onboarding-request).
> [!NOTE]
> At this time it is still being decided how SPNs should align with Proxima stamps. Currently our production and proxima stamps all share the same production SPN. In the future this may change to one SPN per stamp, or a separate SPN for production and a shared SPN for proxima stamps, etc. This is TBD and the [CosmosDB Paved Path team](https://github.com/github/CosmosDB/blob/main/docs/proxima.md) is still identifying the ideal path.
## Adding a New Stamp
In an effort to prevent this doc from getting out of date, links will be provided that point to the cosmos paved path docs whenever possible. Sections in this doc will provide notes/strategies to supplement the paved path docs.
>[!WARNING]
> Be careful when updating attributes of our Cosmos DB accounts. Many of the resources in other repos (such as private links and RBAC) use Azure Resource Ids to identify the correct Azure resource. These Resource Ids look more like a URL and contain things like the resource group for the particular Cosmos DB account. If you are going to be adjusting anything for an existing Cosmos DB account, ensure it will not result in changes to the Resource Id.
### TFE Workspace
Each stamp needs it's own Terraform Workspace, which can be created manually in the TFE UI.
https://github.com/github/CosmosDB/blob/main/docs/deployment.md#creating-a-workspace
### Terraform Plan
Each stamp needs it's own Terraform plan associated with it's infrastructure. You can copy the `main.tf` and `versions.tf` files from any of the existing Proxima stamps and update details as needed to reflect the new stamp you are creating. In addition to creating the new directory, you will also have to edit a few existing files.
- `config/terraform/application/constants.tf` contains the regions for each stamp and should be updated to include the new stamps preferred primary and secondary regions.
- `.github/workflows/terraform-branch-deploy.yml` contains information required for Terraform PR deployments, including the supported targets. You should update `environment-targets` to include the new stamp.
Once the files are updated you should run `terraform init` in the stamp's Terraform directory, ex. `config/terraform/<stamp_name>`. This will generate a `.terraform.lock.hcl` file that you should commit to the repo. The file is not required to run the standard PR Terraform planning and applying logic, but is necessary if we ever need to run specific commands from a codespace in the future.
Once the Terraform plan is created, follow the deployment steps in the paved path docs to create the infrastructure in Azure: https://github.com/github/CosmosDB/blob/main/docs/deployment.md#performing-a-deployment. You must create the resources in Azure before you can complete future steps.
### Private Links
Communication with Proxima stamps is only supported via Azure Private Links. When making your additions to the [Sites](https://github.com/github/sites) and [Puppet](https://github.com/github/puppet) repos you can look for the existing Licensify resources to see how our current stamps are implemented.
https://github.com/github/CosmosDB/blob/main/docs/networking.md#privatelink
### Azure RBAC
The recommended authentication practice for Production is Role Based Access Control.
https://github.com/github/CosmosDB/blob/main/docs/application-authentication.md#role-based-access-control-rbac-recommended-for-production
### Kubernetes
In order to deploy the stamp we need to provide the Kuberetes files. Our Kustomize directory is split apart by stamp, similar to Terraform. Within `config/kustomize/overlays` you should see a directory for each existing stamp, and you can use these to create a new Kustomize directory for the new stamp.
Once the Kustomize files are finished you need to run `script/kustomize` to generate the Kubernetes files.
## Useful Guides
### Importing existing resources into Terraform
If there are ever existing resources in Azure that you want to import into Terraform management you will need to run `terraform import` from within a codespace. Before you can run the commands you will need to be logged into Terraform: `terraform login terraform.githubapp.com`. You also need to ensure that there is a `.terraform.lock.hcl` file for the stamp you are attempting to import resources for. If there isn't you won't be able to access the providers when you run the import command. You can generate the file by running `terraform init` in the stamp Terraform directory (make sure to commit that file once you're done so the next engineer doesn't have to do the same). Now we can run the import command, which has this syntax: `terraform import <resource_name> <resource_id>`. The resource name you can find from running `terraform plan` and noting the resource name provided for the resource-to-be-created that you want to import. The resource id you can find in Azure in the JSON view of a Cosmos DB account. Note that this only includes the Cosmos DB account info and for resources such as a Cosmos DB container you will need to append the extra details yourself, ex:

`terraform import azurerm_cosmosdb_sql_container.licensify "/subscriptions/ff6a70fc-0a30-4bf2-a717-6e53896ff59f/resourceGroups/licensify-prod-weu-01/providers/Microsoft.DocumentDB/databaseAccounts/licensify-prod-weu-01/sqlDatabases/licensify/containers/licensify`

You can find some useful information about this process in the paved path migration docs: https://github.com/github/CosmosDB/blob/main/docs/migrate-to-multi-target.md#full-terraform-migration
