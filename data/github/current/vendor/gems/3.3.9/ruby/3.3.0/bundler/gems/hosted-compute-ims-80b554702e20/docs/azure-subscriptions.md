# Subscriptions

## Background

The IMS service manages a set of subscriptions within the `githubazure` tenant for storing image definitions and versions for both Customer and Curated images.

## Service Tree

As per MSFT requirements the Hosted Compute IMS service is registered within the MSFT Service Tree. This information dictates who owns this service, how it's billed and which subscriptions make up this service.

Our structure is as follows:

```
Service Tree/
└── Division: Cloud + AI platform/
    └── Organization: Github (Independent)/
        └── Service Group: GitHub Compute Products/
            └── Service: Hosted Compute Image Management Service/
                └── Subscriptions: /
                    ├── GitHub Hosted Compute IMS - Prod - [001 - N]
                    ├── GitHub Hosted Compute IMS - Lab [001 - N]
                    ├── GitHub - NonProd - Dev - Hosted Compute IMS - 001
                    └── GitHub - NonProd - Dev E2E - Hosted Compute IMS - 001
```

## Subscription List

Hosted Compute IMS currently supports 2 environments: `lab` and `production`.  
For each environment, we have a set of Azure subscriptions in `githubazure` Azure tenant where 1 subscription is typically reserved for Curated image definitions and versions, with the remaining for Customers' images.

Azure Subscription naming has the following convention:
- `GitHub - NonProd - Lab - Hosted Compute IMS - 001`, `GitHub - NonProd - Lab - Hosted Compute IMS - 002`, etc
- `GitHub - Prod - Hosted Compute IMS - 001`, `GitHub - Prod - Hosted Compute IMS - 002`, etc

## Subscription Access

## Reader Access
For reader access to **lab** and **prod** subscriptions you must belong to the following management groups respectively:
```
azure-hosted-compute-ims-lab-contributor
azure-hosted-compute-ims-prod-contributor
```

## JIT Access

In order to create/deploy resources you must perform a JIT request. You can use the [JIT Bouncer](https://jit-okta-bouncer.githubapp.com/azure) or ChatOps:

Perform the JIT request against the environment specific management group. E.g:

```
.jit me to azure-hosted-compute-ims-lab-contributor in azure for <duration> because <reason>
```

Once you've requested JIT access you can access the portal in the normal way where you'll now be able to create resources within the associated subscriptions.

![image](https://github.com/github/hosted-compute-ims/assets/88484921/36981cda-bd0e-4731-8e6e-8e7c4db50771)
 
