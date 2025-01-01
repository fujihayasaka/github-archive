# Clients + Stats Info

This is meant to be a living document (to the best of our ability) to keep track of Authnd client implementations and the available stats emitted from those implementations.

## Go Clients

### Available Go Client Stats

See [GitHub Code Search](https://cs.github.com/?q=repo%3Agithub%2Fauthnd%20authnd.client.%20path%3A%2F%5Eclient%5C%2F%2F&scopeName=All%20repos&scope=).

- `authnd.client.request`
  - used in `Authenticator`, `CredentialManager`, and `MobileDeviceManager` APIs.
- `authnd.client.timing`
  - used in `Authenticator`, `CredentialManager`, and `MobileDeviceManager` APIs.
- `authnd.client.retries`
  - used in `httpClientOptions` middleware when retries are enabled. Enabled by default. Clients can opt out of retries using `WithoutRetries` option in the client constructor.
- `authnd.client.retries.exceeded`
  - used in `httpClientOptions` middleware when retries are enabled. Enabled by default. Clients can opt out of retries using `WithoutRetries` option in the client constructor.

### Go Client Implementations

|Repo|Code Search|Retries|Statter|Statter Prefix|
|---|---|---|---|---|
|`github/goproxy`|[link](https://cs.github.com/github/goproxy/blob/68efb41aa2600fb48aff1ff744f9b4c8807f8a14/cmd/goproxy/main.go?q=github.com%2Fgithub%2Fauthnd+repo%3Agithub%2Fgoproxy#L103-L109)| :x: |  :x: | n/a |
|`github/insights-code`|[link](https://cs.github.com/github/insights-code/blob/d40b3710640d8d748f7e1c78137c044c52d5c10a/services/api/services/authenticator.go?q=repo%3Agithub%2Finsights-code+github.com%2Fgithub%2Fauthnd%2Fclient+#L28-L31)| :heavy_check_mark: | :x: | n/a |
|`github/token-scanning-service`|[link](https://cs.github.com/github/token-scanning-service/blob/794f4bb2db1e6a26e7a9aa302da2abc8f303736a/ts/notifiers/notifier_service.go?q=github.com%2Fgithub%2Fauthnd%2Fclient+repo%3Agithub%2Ftoken-scanning-service#L58-L64)| :heavy_check_mark: |  :heavy_check_mark: | token_scanning_service (ex: `token_scanning_service.authnd.client.timing`) |

## Ruby Clients

### Available Ruby Client Stats

See [GitHub Code Search](https://cs.github.com/github/authnd?q=repo%3Agithub%2Fauthnd+authnd.client+path%3A%2F%5Eruby%5C%2F%2F).

The Ruby client has some [_special sauce_](https://cs.github.com/github/authnd/blob/f395a827b74915a931b68eb20da6cd071a89c40f/ruby/lib/authnd-client/client/middleware/base.rb?q=repo%3Agithub%2Fauthnd+authnd.client+path%3A%2F%5Eruby%5C%2F%2F#L25) coded into it's middleware for instrumentation. Any `instrument` call from defined middleware will instrument the format `"authnd.client.#{middleware_name}.#{operation}"` (where `operation` is the actual operation performed from the middleware).

You can narrow down where we are calling instrumentation within the client with [this GitHub Code Search](https://cs.github.com/github/authnd?q=repo%3Agithub%2Fauthnd+instrument%28+path%3A%2F%5Eruby%5C%2Flib%5C%2F%2F).

- `authnd.client.retry.tried`
  - used in retry middleware, which is _not_ added to any functions by default
- `authnd.client.retry.succeeded`
  - used in retry middleware, which is _not_ added to any functions by default
- `authnd.client.retry.failed`
  - used in retry middleware, which is _not_ added to any functions by default
- `authnd.client.retry.waited`
  - used in retry middleware, which is _not_ added to any functions by default
- `authnd.client.timing.request`
  - used in timing middleware, which is _not_ added to any functions by default

### Ruby Client Implementations

|Repo|Code Search|Retries|Instrumenter|Instrumentation is reported to Datadog|Other Info|
|---|---|---|---|---|---|
|`github/github`|[link](https://cs.github.com/?q=require%20%22authnd-client%22%20repo%3Agithub%2Fgithub&scopeName=github&scope=org%3Agithub)| implements on [some methods](https://cs.github.com/github/github?q=Authnd%3A%3AClient%3A%3AMiddleware%3A%3ARetry+repo%3Agithub%2Fgithub) |  :heavy_check_mark: | :heavy_check_mark: | - [Forwards instrumentation to dogstats](https://cs.github.com/github/github?q=GitHub.subscribe+%22authnd.client.)<br/>- [Sends dogstat distribution for each request duration in MS](https://cs.github.com/github/github/blob/7c7ccb7284dcbe0607e0ecf41336b15ecc82417f/lib/github/faraday_middleware/datadog.rb?q=rpc.%23%7B%40service_name%7D.dist_time#L62) |
