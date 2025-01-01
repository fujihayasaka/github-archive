# Proxima

NOTE: In all examples, make sure you change the placeholder $new_stamp with the name of the new stamp, for example `prod-sdc-01`. Alternatively you can set an environment variable `export new_stamp=prod-sdc-01`

## Creating new Stamp for Notifyd

### Setting up vault variables

#### Loging into vault 

[Vault](https://thehub.github.com/security/security-operations/vault/) is where we store our sensitive credentials. It is available via [production shell access](https://thehub.github.com/security/security-operations/production-shell-access/). 

```bash
ssh bastion.githubapp.com
ssh -A shell.service.ac4-iad.github.net
. vault-login
```

#### How to setup vault env
```bash
vault-secret --application notifyd --environment $new_stamp --catalog-service notifyd --init
```

#### How to configure the secret keys and urls
```bash
vault-secret --application notifyd --environment $new_stamp --key MONOLITH_TWIRP_API_HMAC_KEY --value-from-file <(od -x -An -N32 /dev/urandom | tr -d ' \n')
vault-secret --application notifyd --environment $new_stamp --key TWIRP_API_HMAC_KEYS --value-from-file <(od -x -An -N32 /dev/urandom | tr -d ' \n')
vault-secret --application notifyd --environment $new_stamp --key GOOGLE_FCM_PRIVATE_KEY --value-from-file <(vault-secret --application notifyd --environment production --key GOOGLE_FCM_PRIVATE_KEY | tr -d '\n')
vault-secret --application notifyd --environment $new_stamp --key FAILBOT_HAYSTACK_URL --value-from-file <(vault-secret --application notifyd --environment production --key FAILBOT_HAYSTACK_URL | tr -d '\n')

# We require values for the application to start, but we don't require credentials for the service, thus we use `not-used`
vault-secret --application notifyd --environment $new_stamp --key GLB_BALANCED_MAIL_SMTP_PASSWORD --value not-used
vault-secret --application notifyd --environment $new_stamp --key GLB_BALANCED_MAIL_SMTP_USER --value not-used
```

#### How to provision an aqueduct API key

Execute the following chatop command, replacing `<new_stamp>` with the name of the new stamp.
Please note that the app parameter is correct as shown! It should be `notifyd-production` for all environments.
This command will generate a new API key for the stamp in the `aqueduct-client-notifyd-production` vault.
```
.aqueduct@<new_stamp> generate-api-key app=notifyd-production
```

Add federation config for the new stamp. This will sync the aqueduct client secrets from `aqueduct-client-notifyd-production` to our `notifyd` vault.
Federated secrets config for aqueduct lives [here](https://github.com/github/secrets-federation/tree/main/config/federation/aqueduct-client-notifyd-production).

#### How to configure the database urls

1. Add secrets federation for the new stamp to sync MySQL database credentials to our `notifyd` vault. Federated secrets for MySQL live [here](https://github.com/github/secrets-federation/blob/main/config/federation/mysql-users-ext/production/notifyd.yaml).

2. Ensure the `MYSQL_RO_USER`, `MYSQL_RO_PASS`, `MYSQL_RW_USER` and `MYSQL_RW_PASS` keys exist in the new stamp's vault
  ```
  vault-secret -a notifyd -e $new_stamp
  ```

3. Execute the following two commands to insert new secrets for `PRIMARY_DB_URL` and `REPLICA_DB_URL`
  ```
  vault-secret -a notifyd -e $new_stamp -k PRIMARY_DB_URL -v "$(vault-secret -a notifyd -e $new_stamp -k MYSQL_RW_USER):$(vault-secret -a notifyd -e $new_stamp -k MYSQL_RW_PASS)@tcp(db-mysql-$new_stamp-rw.service.$new_stamp.github.net:6033)/notifyd"

  vault-secret -a notifyd -e $new_stamp -k REPLICA_DB_URL -v "$(vault-secret -a notifyd -e $new_stamp -k MYSQL_RO_USER):$(vault-secret -a notifyd -e $new_stamp -k MYSQL_RO_PASS)@tcp(db-mysql-$new_stamp-ro.service.$new_stamp.github.net:3306)/notifyd"
  ```

#### How to configure the service url
The service URL for new stamps follows the pattern `http://notifyd.notifyd-<stamp>.svc.cluster.local:8080`, where `<stamp>` should be replaced by the stamp name. e.g. `prod-sdc-01`.

Insert as the `NOTIFYD_URL` key in vault.
```
vault-secret --application notifyd --environment prod-ae-01 --key NOTIFYD_URL --prompt
```

#### Federate secrets to the monolith 
Create federated secrets config for the new stamp. This will sync secrets from our `notifyd` vault to the `github` vault. Federated secrets config lives [here](https://github.com/github/secrets-federation/tree/main/config/federation/notifyd).

#### All required configurations for the notifyd vault
```json
{
  "AQUEDUCT_API_KEY": "See instructions above",
  "AQUEDUCT_API_KEY_VERSION": "See instructions above",
  "FAILBOT_HAYSTACK_URL": "See instructions above",
  "GOOGLE_FCM_PRIVATE_KEY": "See instructions above",
  "MONOLITH_TWIRP_API_HMAC_KEY": "See instructions above",
  "PRIMARY_DB_URL": "See instructions above",
  "REPLICA_DB_URL": "See instructions above",
  "TWIRP_API_HMAC_KEYS": "See instructions above",
  "NOTIFYD_URL": "See instructions above",
}
```

### Create kustomize/kubernetes configuration for the new stamp

Execute the following make command:

```bash
make new-stamp NEW_STAMP=$new_stamp
```
