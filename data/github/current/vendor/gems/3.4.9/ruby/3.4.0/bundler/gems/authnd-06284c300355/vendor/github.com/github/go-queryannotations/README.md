# Go Query Annotations

Add query annotations to your SQL queries to help with debugging and monitoring similar to [Rails QueryLogs](https://api.rubyonrails.org/classes/ActiveRecord/QueryLogs.html).

Turn

```sql
SELECT u.id, u.name FROM users u WHERE u.id = 1
```

into

```sql
SELECT u.id, u.name FROM users u WHERE u.id = 1 /*application:myapp,deployed_to:production,request_id:B8DE:1C1BD5:983574:A30E8C:6693776F*/
```

Downstream tools like quoroner or query-harvester can use these annotations for query attribution to aid with debugging and monitoring.

> [!WARNING]
> While keys and values are url-encoded, you must never pass user-controlled input directly as a query annotation.

> [!WARNING]
> Do not include EUII or PII in query annotations.

## Setup

The easiest way to add query annotations is to wrap the `"database/sql"` connection. Instead of:

```go
import (
  "database/sql"
)

db, err := sql.Open("mysql", "user:password@/dbname")
```

use

```go
import (
  "github.com/github/go-queryannotations/sql"
)

db, err := annotatesql.Open("mysql", "user:password@/dbname",
  // Options
  queryannotations.WithFormatter(&queryannotations.MarginaliaFormatter{}),
  // App-wide query annotations
  queryannotations.WithAnnotations(
    annotation.Application("myapp"),
    annotation.DeployedTo("production"),
  ),
)
```

Depending on how you open the database connection you can also use:

```go
// OpenDB opens a DB using the given connector
func OpenDB(c driver.Connector, opts ...queryannotations.Option) *sql.DB

// AdaptDB adapts an existing sql.DB to use query annotations.
//
// It does so by closing the existing DB, wrapping the driver, and re-opening the connection.
func AdaptDB(db *sql.DB, dsn string, opts ...queryannotations.Option) (*sql.DB, error)
```

### sqlx

To use with `jmoiron/sqlx`, you can use the `sqlx` package:

```go
import (
  "github.com/github/go-queryannotations/sqlx"
)

db, err = annotatesqlx.Open("mysql", "user:password@/dbname",
  // App-wide query annotations
  queryannotations.WithAnnotations(
    annotation.Application("myapp"),
  ),
)
```

## Manually annotating queries

Instead of wrapping the database driver, you can also annotate queries manually:

```go
annotations := []queryannotations.Annotation{
  // App-wide query annotations
  annotation.Application("myapp"),
  annotation.DeployedTo("production"),

  // Request specific query annotations
  func(ctx context.Context) *annotation.Annotation {
    return &queryannotations.Annotation{
      Key:      "request_id",
      Value:    requestid.GetGitHubRequestID(ctx),
    }
  },
}

// ...

ctx = queryannotations.WithQueryAnnotations(ctx, annotation.Route(r.Method+" "+r.URL.Path))

row := db.QueryRowContext(
  ctx,
  // Annotate the query
  queryannotations.Annotate(
    ctx,
    "SELECT id, name FROM users WHERE id = 1",
    queryannotations.WithAnnotations(annotations),
  ),
  // Will run:
  // SELECT id, name FROM users WHERE id = 1 /*application:myapp,deployed_to:production,request_id:000f8753-79e8-4fac-8a47-a07d63f8b1a6,route:GET+%2F*/
)
if err := row.Scan(); err != nil {
  http.Error(w, err.Error(), http.StatusInternalServerError)
  return
}
```

## Adding query annotations

### Global

Annotations that don't change throughout the lifetime of the application should be added when opening the SQL connection:

```go
db, err := sql.Open("mysql", "user:password@/dbname",
  // App-wide query annotations
  queryannotations.WithAnnotations(
    annotation.Application("myapp"),
    annotation.DeployedTo("production"),
  ),
)
```

### Request-scoped

There are two ways to add request scoped query annotations:

1. When opening the connection
    ```go
    db, err := sql.Open("mysql", "user:password@/dbname",
      // Request specific query annotations
      queryannotations.WithAnnotations(
        func(ctx context.Context) *queryannotations.Annotation {
          // This is called whenever a query needs to be annotated. This is an example of integrating with github/go-requestid
          return &queryannotations.Annotation{
            Key:       "request_id",
            Value:     requestid.GetGitHubRequestID(ctx),
          }
        },
      ),
    )
    ```
    or when annotating a query:
    ```go
    queryannotations.Annotate(ctx, "query",
      queryannotations.WithAnnotations(
        func(ctx context.Context) *queryannotations.Annotation {
          // This is called whenever a query needs to be annotated. This is an example of integrating with github/go-requestid
          return &queryannotations.ComponentValue{
            Component: "request_id",
            Value:     requestid.GetGitHubRequestID(ctx),
          }
        },
      ),
    })
    ```

2. Add them to the context during the request lifecycle:

```go
func(w http.ResponseWriter, r *http.Request) {
  ctx := r.Context()

  // Add request specific annotations
  ctx = queryannotations.WithQueryAnnotations(ctx, annotation.Route("GET /"))

  // ...

  // Later, execute a query for the request using an adapted db instance
  row := db.QueryRowContext(ctx, "SELECT 1 FROM table")

  // or

  query := queryannotations.Annotate(ctx, "SELECT 1 FROM table")
}
```

### Options

* `WithFormatter(formatter Formatter)` - Use the given formatter, defaults to `&MarginaliaFormatter{}`
* `WithPrepend()` - Prepends the query instead of appending it, defaults to `false`

## Manually generate query comment

To manually add annotations to a query, you can use:

```go
func GenerateComment(ctx context.Context, opts ...queryannotations.Option) string
```

## Parsing query comments

To parse out key/value components from a query _with_ query annotations comments, you can use:

```go
func ParseQueryWithComment(ctx context.Context, text string, opts ...queryannotations.Option) (query string, comments []string, components []*ComponentValue, err error)
```

## Format

As of today Rails 7 and `github/github` uses the [Marginalia](https://github.com/basecamp/marginalia) format for query tags. That is `/*key:value,key:value2*/`. More and more tools are adopting the [_sqlcommenter_](https://google.github.io/sqlcommenter/spec/) format instead which uses `/*key='value',key2='value2'*/`, with url-encoded keys and values. Rails 8 [will also change the default](https://github.com/rails/rails/blob/9ba208c16835f4a174ae9fd385ebc18972d758a4/activerecord/lib/active_record/query_logs.rb#L16-L18) to the sqlcommenter format.


Currently this library defaults to the the Marginalia format that we use in `github/github`. If you want to use the SQLCommenter format, use the `WithFormatter` option with the `queryannotations.SQLCommenterFormatter` type but be aware that downstream parsers might only expect the Marginalia format for now.
