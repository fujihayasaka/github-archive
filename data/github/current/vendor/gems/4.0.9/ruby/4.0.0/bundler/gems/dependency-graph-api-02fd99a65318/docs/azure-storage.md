# Azure Storage

## Important Note

As of May 2023, the Azure storage buckets are not used in development or production by
Dependency Graph API. The "Snapshots" blob concept was taken over to [Dependency Snapshots API](https://github.com/github/dependency-snapshots-api), which has its own Azure Blob Store accounts for dotcom and Proxima stamps.

## Overview
This is a quick doc to describe how to access, introspect on, and manage our DG-API Azure Blob Storage accounts, containers etc.

## Access
You can install the `az` tool locally, but this requires extra steps to obtain the creds required. Recommendation from Azure pros is to use the UI "console" as detailed below.

Always being by logging into `https://portal.azure.com` using your `<github_login>@githubazure.com` email as username. As with accessing any MSFT resources, auth methods (phone, 2FA etc.) will vary.

### Storage Accounts
Once logged in, you can access the dev and prod storage accounts at the links below. Note, the dev account is currently unused (by DG anyway!)
- [production](https://portal.azure.com/#@githubazure.onmicrosoft.com/resource/subscriptions/e8881bf9-9397-4235-b583-be4ab4a99711/resourceGroups/dg-api-prod/providers/Microsoft.Storage/storageAccounts/proddepreviewstorage/overview)
- [development](https://portal.azure.com/#@githubazure.onmicrosoft.com/resource/subscriptions/bf2356ad-9fb5-427d-8070-63c26283d1ae/resourceGroups/dg-api-development/providers/Microsoft.Storage/storageAccounts/devdepreviewstorage/overview)

In the top-right icon tray, look for the "terminal icon" and click to obtain a bash or PowerShell terminal session. If prompted, you can create storage access this won't hurt anything.

One you have a terminal, you can run `az` commands as shown below. You will need to obtain the `--account-key <KEY>` and matching `--connection-string <CONNSTRING>` for each storage account by browsing the left-hand nav column from each overview page. In the nav column, look for `Storage + networking` and `Access Keys`. Direct links below:
- [production](https://portal.azure.com/#@githubazure.onmicrosoft.com/resource/subscriptions/e8881bf9-9397-4235-b583-be4ab4a99711/resourceGroups/dg-api-prod/providers/Microsoft.Storage/storageAccounts/proddepreviewstorage/keys)
- [development](https://portal.azure.com/#@githubazure.onmicrosoft.com/resource/subscriptions/bf2356ad-9fb5-427d-8070-63c26283d1ae/resourceGroups/dg-api-development/providers/Microsoft.Storage/storageAccounts/devdepreviewstorage/keys)

**WARNING!**:
1. **DO NOT** accidentally click `Rotate Keys` on the access keys pages!
1. Use **Show Keys** (top of each page listing) to display copyable `Key` (for `--access-key`) and `Connection String` (for `--connection-string`)
1. Make sure to copy matching key and container string for the env you'll be working in
1. There are 2 keys listed per page (to enable rotation) and at time of this writing, `Key 2` worked for me from both pages

## Commands
Once you have obtained the keys you need for the storage account you'll be working on, and an `az` shell from the web UI, you're ready to do things! Some example commands below. Some important arguments to the `az storage blob ...` commands:

- `--account-name` the storage account; one of `proddepreviewstorage` or `devdepreviewstorage`
- `--container-name` (legacy arg: `--source`) should always be `dg-snapshots` for our snapshot blobs
- `--account-key` one of the Keys listed on the Azure Portal for each storage account at `Overview -> Storage + networking -> Access Keys`
- `--connection-string` value associated with each Key listed on the Azure Portal for each storage account at `Overview -> Storage + networking -> Access Keys`

Example commands:
```
### Assuming production env "proddepreviewstorage":

# List all stored blobs:
> az storage blob list --account-name proddepreviewstorage --container-name dg-snapshots --connection-string “<CONN_STRING>” --account-key “<KEY>”

# Delete individual blobs by "name" entries found during list command step:
> az storage blob delete --account-name proddepreviewstorage --container-name dg-snapshots --connection-string “<CONN_STRING>” --account-key “<KEY>" --name "<BLOB_NAME>"

# Batch delete all stored blobs (can use dates or pattern/path matching, see "az" CLI docs!)
> az storage blob delete-batch --account-name proddepreviewstorage --source dg-snapshots --connection-string "<CONN_STRING>" --account-key "<KEY>"
```
