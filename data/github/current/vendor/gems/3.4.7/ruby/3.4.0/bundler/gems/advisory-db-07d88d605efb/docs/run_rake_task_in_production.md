# How to a run an AdvisoryDB rake task in production

AdvisoryDB is a Moda app, and so running a rake task in production requires some special commands.

#### Log into bastion

```
ssh shell
```

#### Log into shell on advisory-db moda app

```
gh-k8s-shell -n advisory-db-production
```

for canary, use: 

```
gh-k8s-shell -n advisory-db-staging
```

If that command gives trouble, try this:
```
. vault-login
gh-kubeconfig general-2-ac4-iad
```

#### Run `rake`

From here all the rake tasks are available through `bin/rake`.

Show all the available tasks:
```
bin/rake -T
```

Or run a specific one:
```
bin/rake advisory_db:backfill:backfill_list_of_ghsa_ids
```

 
