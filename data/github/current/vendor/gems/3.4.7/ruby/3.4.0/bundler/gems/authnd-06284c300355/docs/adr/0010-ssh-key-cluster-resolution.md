# 10.  SSH Key Cluster Resolution 

Date: 2020-11-25

## Status

Approved

## Context

Authnd currently uses the mysql1 public_keys table when handling authentication requests. 
We want the option to switch the service between using the mysql1 and authnd clusters for SSH public key look-ups, 
or set the service to look in the authnd cluster first and fall-back to the mysql1 cluster when a key isn't present. 
This service behavior would hypothetically allow Authnd to handle requests before migrating over the data from the mysql1 public_keys table so long as
our replication process is consistant. This would also allow us to continue to use the gitauth-authnd experiment as a canary to make sure that our
service behavior reflects gitauth's, which we would otherwise be unable to do before the mysql1 public_keys migration.

In order to do this we need to decide how to handle enabling/disabling different logic paths in the authnd service. 

## Decision

We'll use a configuration variable stored in Vault to manage this authnd service public_keys table cluster change.

## Option 1: Environment variable in Authnd Vault

We would create a new environment variable in the github vault that would be injected into the environment variables used by the authnd on start-up.

## Consequences

The authnd service would need to be redeployed for any public_key cluster change to take effect. 
Storing the value in vault would make it possible to update the cluster configuration for both environments from the same location.
This might not be viable long term or could clutter our vault if we continue to add vault secrets in these situations.   

## Option 2: Feature_flag table  

We would create a table to read from to manage this scenario, which would allow for more complex feature flagging if nessesary later.

## Consequences

This change involves more overhead with creating the schema, migrating the table and implementing the store to fetch this information. 
This solution would add an additional MySQL call to each authentication request. Additionally the staging and production environments current both rely on the same tables.
We will soon have a separate staging database - but the fact that we curently don't complicates this solution. We would either not be able to specify feature flag status differences between staging and production, 
or we could design the table to allow that and would need to revisit or fix the design after our staging database is provisioned. 
