# Licensing and Terraform

Our licensing Azure Blob Storage accounts and CosmosDB accounts are managed by Terraform.

We have one terraform workspace per stamp, which can be found and managed in the [GitHub TFE UI](https://terraform.githubapp.com/app/azure-licensing/workspaces).

Our branch deploy and dependabot scripts communicate with TFE via an API token. This token is a TEAM token and can be regenerated at the [tfe-licensing team page](https://terraform.githubapp.com/app/azure-licensing/settings/teams/team-4EiCM4DYg52Jvvnq) in the UI. When this token gets updated, it will need to be updated in repo secrets settings:

- [dependabot](https://github.com/github/licensify/settings/secrets/dependabot) as TFE_TOKEN
- [actions](https://github.com/github/licensify/settings/secrets/actions) as TFE_TOKEN
- [codespaces](https://github.com/github/licensify/settings/secrets/codespaces) as GH_CS_TERRAFORM_LOGIN_TOKEN

## Importing existing resources

If you ever need to run terraform import to import an existing resource into terraform you will first need to connect to the dev vpn. If you are running licensify in a codespace, the dev-vpn binary shouldy aready be installed.

Run `dev-vpn connect`.

You will also need to be able to communicate with vault services. To get this working, on a bastion or shell host, login to vault with the normal `. vault-login` process. Next run `echo $VAULT_TOKEN` to get your token. Then in the codespace, run `export VAULT_TOKEN={value from ops-shell}`.

With this values set the import commands should be able to run sucessfully.
