# Database Improvements

This proposal focuses on some low level database improvements for `notifyd`.
The problem statement is captured in [this brief][brief].

## Implement read replicas

For implementing support for read replicas we need two `sqlx.DB`
connections available, one for reading, and one for writing. Implemented in
the `DIContainer` this kinda looks like this:

```go
type DIContainer struct {
  ...

  dbReadOnly        *sqlx.DB
  dbWrite           *sqlx.DB
}
```

For reading queries the `dbReadOnly` connection should be used and for writing
queries the `dbWrite` connection. That way it is every explicit in the code at
any given time which type of connection is used for a query and which database
instance it connects to. In order to support this we are adding a new method
to the `config` package. The existing `cfg.DBConnection()` becomes
`cfg.DBReadOnlyConnection()` and gets changed to use the read replica
connection string. We are also adding a new method `cfg.DBWriteConnection()`
that returns a writable connection.

### Rollout
In order to make the rollout easy to track and the work packets easier to
split up, we are gonna change the `DIContainer` first into an intermediate
structure that looks like this.

```go
type DIContainer struct {
  ...

  db                *sqlx.DB
  dbReadOnly        *sqlx.DB
  dbWrite           *sqlx.DB
}
```

Here the `db` connection is the existing one and considered legacy. Any code
parts still using it will have to change to explicitly use the `dbReadOnly` or
`dbWrite` connection. Once everything is moved over, the `db` connection can
be removed.

## Implement write throttling

As a first step for supporting throttling we are adding a function similar to
the existing `mysql.WithRetries` one we already have but a bit more
configurable. The code can kinda look like this as an example implemented in
the existing `mysql` package.

```go
package mysql

import (
  "context"
  "time"

  errors "github.com/github/notifyd/internal/pkg/errors"
  "github.com/github/notifyd/internal/pkg/o11y/logs"

  freno "github.com/github/go-freno-client"
  stats "github.com/github/go-stats"
)

// ThrottlableFunction is a function that can be run throttled
type ThrottlableFunction func() error

// Throttler exposes an interface for throttling mysql writes
type Throttler interface {
  RunThrottled(context.Context, ThrottlableFunction) error
  Wrap(context.Context, ThrottlableFunction) ThrottlableFunction
}

// DefaultThrottler exposes a
type DefaultThrottler struct {
  cluster        string
  logger         logs.Logger
  statter        stats.Client
  frenoThrottler freno.Throttler
}

// NewThrottler returns a new DefaultThrottler
func NewThrottler(cluster string, logger logs.Logger) *DefaultThrottler {
  return &DefaultThrottler{
    cluster:        cluster,
    logger:         logger,
    frenoThrottler: freno.DefaultThrottler,
  }
}

// RunThrottled takes a throttableFunction and sees if it can run it
func (d *DefaultThrottler) RunThrottled(ctx context.Context, f
ThrottlableFunction) error {

  var err error
  start := time.Now()
  defer func() {
    d.statter.DistributionMs("freno.throttle.time", errors.ToStats(err),
time.Since(start))
    d.statter.Counter("freno.throttle.count", errors.ToStats(err), int64(1))
  }()
  err = freno.WaitOnThrottler(ctx, d.frenoThrottler)
  if err != nil {
    if _, ok := err.(*freno.ErrTimeout); ok {
      err = errors.Wrap(err, "freno error").With(errors.MarkRetriable())
    } else {
      err = errors.Wrap(err, "freno error")
    }
    return err
  }

  return f()
}

// Wrap wraps a throttlable function to be executed later
func (d *DefaultThrottler) Wrap(ctx context.Context, f ThrottlableFunction)
ThrottlableFunction {
  return func() error {
    return d.RunThrottled(ctx, f)
  }
}
```
This throttler then can be used directly:

```go
throttler := mysql.NewThrottler("notifyd", logger, statter)
queryF :=  func() error { return c.DB.SelectContext(ctx, "INSERT INTO....") }
err := throttler.RunThrottled(ctx, queryF)
```

Or in conjunction with retries, for which we first would have to
change `mysql.Retries` to use the `internal/pkg/errors` package as well:

```go
throttler := mysql.NewThrottler("notifyd", logger, statter)
queryF :=  func() error { return c.DB.SelectContext(ctx, "INSERT INTO....") }
err := mysql.WithRetries("insert_some_data", logger, throttler.Wrap(ctx, queryF))
```

#### Rollout
The rollout of this can happen gradually. We can implement the throttling
functions first and then change eligible call sites as we see fit.






[brief]: https://github.com/github/notifyd/blob/main/docs/briefs/database-improvements.md
