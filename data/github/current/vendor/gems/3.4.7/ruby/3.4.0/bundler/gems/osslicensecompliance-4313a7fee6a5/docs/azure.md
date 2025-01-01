# Azure

This project uses Azure for blob storage.
This is managed by Terraform Enterprise.

Subscription: `GitHub - Prod- Supply Chain - osslicensecompliance`
Subscription ID: `d206e280-49d9-4a86-b28c-54734f42ca2c`


## Terraform Workspaces

Terraform workspaces are in Dependency Graphs [azure-dsp-dependency-graph-prod](https://terraform.githubapp.com/app/azure-dsp-dependency-graph-prod/workspaces).

### Staging:

Workspace: [osslicensecompliance-staging](https://terraform.githubapp.com/app/azure-dsp-dependency-graph-prod/workspaces/osslicensecompliance-staging)
Config directory `config/terraform/staging`

Azure storage account: `olcstaging`
Contains a container per policy type:
- `repository-policies` 
- `organization-policies` 
- `enterprise-policies` 

### Production 

Workspace: [osslicensecompliance-production](https://terraform.githubapp.com/app/azure-dsp-dependency-graph-prod/workspaces/osslicensecompliance-production)

Config directory `config/terraform/production`

Azure storage account: `olcproduction`
Contains a container per policy type:
- `repository-policies` 
- `organization-policies` 
- `enterprise-policies` 
