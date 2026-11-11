# OTEL cookbook

## Lightstep recipes

In [Lightstep Explorer](https://app.lightstep.com/github-prod/explorer):

### Get spans for incoming Twirp operations

```
service IN ("dependency-graph-api") AND "rpc.system" IN ("twirp") AND "span.kind" IN ("server")
```

### Get spans for outgoing Twirp operations

```
service IN ("dependency-graph-api") AND "rpc.system" IN ("twirp") AND "span.kind" IN ("client")
```

### Get spans for a specific Twirp operation

Using `GetDependenciesForRepository` as an example:
```
service in ("dependency-graph-api") AND operation IN ("DependencyGraphAPI.v1.RepositoryDependenciesAPI/GetDependenciesForRepository")
```

or, alternatively:
```
service in ("dependency-graph-api") AND "rpc.service" IN ("DependencyGraphAPI.v1.RepositoryDependenciesAPI") AND "rpc.method" IN ("GetDependenciesForRepository")
```
