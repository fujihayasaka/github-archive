# go-staffbar

Helpers for exposing data from Go services back to the dotcom staffbar.

## Exposing database query timings

First add the middleware to your app:

```go
mux.Handle("/", staffbar.Handler(yourHandler))
```

Then setup logging from your database logger to report the query, duration,
and number of results of each query performed:

```go
staffbar.QueryReporterFromContext(ctx).Report(query, duration, count)
```

Then setup dotcom to use the staffbar middleware for the faraday connection
for your service:

```ruby
conn.use GitHub::FaradayMiddleware::Staffbar, url: GitHub.my_service_url
```

Then you should see database timings for your service whenever the staffbar
in dotcom is open and instrumenting queries.

## Contributing

This repository is owned by [@dev-frameworks](https://github.com/github/dev-frameworks/), and we welcome contributions! To learn more about developing and making updates to this repo, please see [the contributing guide](./CONTRIBUTING.md).
