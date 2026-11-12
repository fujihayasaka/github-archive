Staging is an environment that is a subset of production. It currently doesn't use an isolated database, so treat this environment with the same care as production for RW operations!

Currently, the environment only surfaces an additional deployment of our web application and uses the same secrets as our production application.

#### Vault 

The vault for our staging environment is a one time copy of what is in our production environment. This seems to be the common way to get staging environments to work at GH, but it means that a changed production secret may need to be replicated into the staging vault.

There is ONE key that has been customized in the staging environment of the vault. The key in question is HMAC_SECRET_ADVISORY_INBOX_GITHUBAPP_COM -- this has a different value in staging than in production intentionally, it's because a different Okta Network Gateway application is in use for staging. If you somehow lose this value, the ONG folks can provide it again.