# Observability

For general observability at GitHub, see [The Hub - Observability](https://thehub.github.com/epd/engineering/dev-practicals/observability/)

## Moda Homepage

Moda resources and deployment can be found on the [Devportal homepage](https://devportal.githubapp.com/devportal/apps/attester)

## Datadog

#TODO 

### Metrics

#TODO

#### Process Stats

#TODO

#### Twirp Stats

#TODO

#### HTTP Stats

#TODO

## Logs - Splunk
#TODO

Logs can be found in [Splunk](https://splunk.githubapp.com/) in the `attester` index:

```text
index IN(attester) kube_namespace=attester-*
```

## App Errors - Sentry

Exceptions are sent to [Sentry](https://github.sentry.io/projects/attester?project=4507781727059968)

## Distributed tracing

#TODO

### Distributed tracing - Development Mode
#TODO
