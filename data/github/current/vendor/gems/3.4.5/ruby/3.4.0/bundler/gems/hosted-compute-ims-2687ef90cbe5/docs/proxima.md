# IMS in Proxima

## What Proxima is solving? 

We want to have small versions of GitHub running on Azure in a given location dedicated to a particular customer instead of deploying GHE clusters.
For example https://staffship-01.ghe.com/ - has no Dotcom repos/issues/prs and is a completely isolated deployment of GitHub.

Before if we would want to deploy a private version of GitHub it would be a GHE or GHAE application with a separate team maintaining that particular deployment.
More GHE instances -> more costs -> more headaches, e.g. there is a GHE manual testing process for the codebase that is potentially 6 months behind the main branch in dotcom.

Proxima fixes this and allows “Private” versions of GitHub, let’s call them `Tenants` to be deployed into different geo-locations Stamps. 
Here is the list of current GitHub Stamps: https://devportal.githubapp.com/proxima/stamps

In each stamp you can pick a tenant, for example https://devportal.githubapp.com/proxima/stamps/staff-wus2-01/tenants/azuredevops-test
What’s important is that the GitHub copy for each Tenant should include a full copy of dotcom and all related services next to it: `authzd`, `aqueduct`, `IMS` - you name it. 

For this effort to succeed - every service including the four nines services should know how to work in the proxima environment when they are deployed to a different stamp, for a particular tenant.

Proxima envs can be used also as part of pre-production deploys as it's done in Dotcom.

### Resources and links

Technical proposal - it’s 2 years old but answers a lot of questions: https://github.com/github/proxima/blob/main/docs/infrastructure-technical-proposal.md

How availability zones work for Proxima https://github.com/github/proxima/blob/main/adr/availability-zones.md

Example of a Moda app deployed to multiple Proxima stamps: https://github.com/github/authzd/blob/master/config/moda/deployment.yaml

Proxima stamp lifecycle https://thehub.github.com/epd/engineering/products-and-services/proxima/stamps/

