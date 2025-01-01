# Deployment

notifyd is deployed with moda and chatops.

## GitHub Flow

We follow the typical GitHub deploy flow

1. Make changes in a branch
2. Open a pull-request
3. Get it approved by your peers
5. If you are happy, deploy to `production`
6. If you are happy, merge your branch

## Deployment

To deploy to all environments:

```
in: #notifications-ops

.qmtd notifyd/$branch
```

If you need to deploy database migrations, read the [migration docs](./development.md#database-migrations)

### Features

This is it. The real deal. Production. Code that runs here affects users.

## Observability

Our [DataDog Dashboard](https://app.datadoghq.com/dashboard/n77-d3g-dqh) gives an overview of the service status.

Anything logged to `STDOUT` will appear in splunk under [`index=notifyd kube_namespace_notifyd-production`](https://splunk.githubapp.com/en-GB/app/gh_reference_app/search?q=search%20index%3Dnotifyd%20kube_namespace%3Dnotifyd-production)
