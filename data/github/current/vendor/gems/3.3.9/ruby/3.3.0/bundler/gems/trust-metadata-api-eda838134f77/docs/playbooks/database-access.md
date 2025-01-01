# Accessing Trust Metadata API Database

> **Note:** You must be connected to the Production VPN to access the database and Vault.

For more information about the database, see [docs/database.md](../database.md).

## Production

- Connect to the production VPN, see setup direction [here](https://thehub.github.com/security/security-operations/production-vpn-access/)
- Get the connection information from Vault. See our [documentation on Vault](../vault.md) for additional details.

```shell
# Connect to Vault bastion and get the connection information
ssh <github-handle>@vault-bastion.githubapp.com
. vault-login
vault-secret --application trust-metadata-api --environment production --key TMA_MYSQL_PASSWORD
exit
```

- Make sure you close your connection to Vault bastion
- Connect to the database from your local machine

```shell
# Connect to the database with the password you got from Vault
mysql --host db-mysql-trust-metadata-api-production-rw.service.github.net --user trust_metadata_api_prod_rw_0 --port 6033 --password --database trust_metadata_api_production
```

You can now run queries against the database.

## Staging

- Connect to the production VPN, see setup direction [here](https://thehub.github.com/security/security-operations/production-vpn-access/)
- Navigate to the [project's DB cluster page on the ProfessorX app](https://professorx.githubapp.com/mysql/cluster/trust-metadata-api-staging), you will find the password for user `vt_app_devel`, which we use to connect with the database on this page.
- Connect to the cluster from your local machine

```shell
mysql -h vitess-vtgate-mysql-staging.service.iad.github.net -u vt_app_devel  -P 10018 -D trust_metadata_api_staging_ks -p
```

You can now run queries against the database.
