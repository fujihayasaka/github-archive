## Terraform Configuration

The infrastructure that we use for migrations-vnext on Azure is
provisioned using Terraform.

### Folder Organization

We use the following folder structure:
* `staging` - contains the terraform configuration for the staging/dev environment
* `staff-wus2-01` - contains the terraform configuration for the Proxima Staffship
* `prod-weu-01` - contains the terraform configuration for the Proxima in Production for West Europe, this is where the Spotify Alpha will be run.