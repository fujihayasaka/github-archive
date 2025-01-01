// asql provides enchanced drop-in replacements for most of the *sql.SQL query methods, with some
// alterations to allow access to error values on single row queries.
//
// Ideally use WithName, e.g `sql.<Method>With(ctx, sql, asql.WithName(...)`, to
// provide a clear operation name for logging/stats/tracing.
//
// adds the following to all queries:
// - tracing
// - circuit breaking
// - the `act_query.time` stat
// - `Body=act_query` log line, with "error=..." set if an error occured
package asql

import (
	"context"
	"database/sql"
	"os"
	"strconv"
	"time"

	"github.com/github/go-kvp"
	"github.com/github/go-queryannotations"
	"github.com/github/go-queryannotations/annotation"
	"github.com/go-sql-driver/mysql"
	errs "github.com/pkg/errors"
	circuit "github.com/rubyist/circuitbreaker"

	"github.com/github/launch/mysqldb"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/callcounter"
	"github.com/github/launch/observability/metrickeys"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/observability/tracing"
	"github.com/github/launch/pkg/mu/muhttp/mw"
)

const (
	maximumReadRetries = 3
	LaunchCluster      = "launch_rw"
	LaunchROCluster    = "launch_ro"
	PayloadsCluster    = "payload"
)

type SQL struct {
	logger      logs
	stats       statter.Statter
	breaker     *circuit.Breaker
	db          *sql.DB
	ClusterName string

	annotations          []annotation.AnnotationOption
	annotationsFormatter queryannotations.Formatter
}

type Execer interface {
	ExecContext(ctx context.Context, sql string, params ...any) (sql.Result, error)
}

type logs interface {
	Log(context.Context, string, ...kvp.Field)
	Debug(context.Context, string, ...kvp.Field)
	Error(context.Context, string, ...kvp.Field)
}

func New(db *sql.DB, logs logs, stats statter.Statter, breaker *circuit.Breaker, clusterName string) *SQL {
	deployedTo := os.Getenv("HEAVEN_DEPLOYED_ENV")

	return &SQL{
		logger:      logs,
		stats:       stats,
		breaker:     breaker,
		db:          db,
		ClusterName: clusterName,
		annotations: []annotation.AnnotationOption{
			annotation.Application("launch"),
			annotation.DeployedTo(deployedTo),
			func(ctx context.Context) *annotation.Annotation {
				requestID := mw.GetGitHubRequestID(ctx)
				if requestID == "" {
					return nil
				}

				return &annotation.Annotation{
					Key:   annotation.RequestIDKey,
					Value: requestID,
				}
			},
		},
		annotationsFormatter: &queryannotations.MarginaliaFormatter{},
	}
}

func (a *SQL) Close() error {
	return a.db.Close()
}

func (a *SQL) QueryContext(ctx context.Context, sql string, params ...any) (res *sql.Rows, err error) {
	return a.QueryContextWith(ctx, sql, nil, params...)
}

func (a *SQL) ExecContext(ctx context.Context, sql string, params ...any) (res sql.Result, err error) {
	return a.ExecContextWith(ctx, sql, nil, params...)
}

// QueryScan is the replacement for .QueryRow, that wraps the scanning operation to allow
// this package to see the error value
func (a *SQL) QueryScan(ctx context.Context, sql string, params []any, dest ...any) (err error) {
	return a.QueryScanWith(ctx, sql, nil, params, dest...)
}

func (a *SQL) ExecContextWith(ctx context.Context, sql string, options Options, params ...any) (res sql.Result, err error) {
	err = a.write(ctx, sql, options, func(sql string) error {
		r, e := a.db.ExecContext(ctx, sql, params...)
		res = r
		return e
	})

	return res, err
}

// QueryTx executes a sql statement using a transaction. You must close the connection and check for errors.
func (a *SQL) QueryTx(ctx context.Context, tx *sql.Tx, sql string, options Options, params ...any) (res *sql.Rows, err error) {
	err = a.read(ctx, sql, options, func(sql string) error {
		// ignore linter here, if we don't check errors/defer close here, the linter will make
		// noise in the code that's calling ths method.
		res, err = tx.QueryContext(ctx, sql, params...) //nolint:rowserrcheck,sqlclosecheck
		return err
	})

	return res, err
}

// ExecTx executes a sql statement using a transaction.
func (a *SQL) ExecTx(ctx context.Context, tx *sql.Tx, sql string, options Options, params ...any) (res sql.Result, err error) {
	err = a.write(ctx, sql, options, func(sql string) error {
		res, err = tx.ExecContext(ctx, sql, params...)
		return err
	})

	return res, err
}

// QueryContextWith executes a sql statement. You must close the connection and check for errors.
func (a *SQL) QueryContextWith(ctx context.Context, sql string, options Options, params ...any) (res *sql.Rows, err error) {
	err = a.read(ctx, sql, options, func(sql string) error {
		// ignore linter here, if we don't check errors/defer close here, the linter will make
		// noise in the code that's calling ths method.
		r, e := a.db.QueryContext(ctx, sql, params...) //nolint:rowserrcheck,sqlclosecheck
		res = r
		return e
	})

	return res, err
}

func (a *SQL) QueryScanWith(ctx context.Context, sql string, options Options, params []any, dest ...any) error {
	return a.read(ctx, sql, options, func(sql string) error {
		row := a.db.QueryRowContext(ctx, sql, params...)
		return row.Scan(dest...)
	})
}

func Params(params ...any) []any {
	return params
}

func (a *SQL) read(ctx context.Context, sql string, options Options, fn func(sql string) error) error {
	var err error

	cfg := configFromOptions(options)
	operation := cfg.opName()
	for i := 0; i < maximumReadRetries; i++ {
		err = a.query(ctx, sql, options, fn)

		if err == mysql.ErrInvalidConn {
			a.logger.Debug(ctx, "retrying database operation due to invalid connection")
			a.stats.Counter(ctx, metrickeys.MySQLRetries, map[string]string{
				metrickeys.OperationName: operation,
				"attempt":                strconv.Itoa(i + 1),
			}, 1)
			continue
		}

		if e, ok := err.(*mysql.MySQLError); ok {
			if e.Number == mysqldb.ServerShutdownErrorCode {
				a.logger.Debug(ctx, "retrying database operation due to server shutdown error")
				a.stats.Counter(ctx, metrickeys.ServerShutdownRetry, map[string]string{
					metrickeys.OperationName: operation,
					"attempt":                strconv.Itoa(i + 1),
				}, 1)
				continue
			}
		}

		return err
	}
	return err
}

func (a *SQL) write(ctx context.Context, sql string, options Options, fn func(sql string) error) error {
	return a.query(ctx, sql, options, fn)
}

func (a *SQL) query(ctx context.Context, query string, options Options, fn func(sql string) error) error {
	cfg := configFromOptions(options)
	operationName := cfg.opName()

	ctx, span := tracing.StartWithOpFuncName(ctx, operationName)
	defer span.End()

	defer func() {
		info := a.db.Stats()
		tags := statter.Tags{}
		if a.ClusterName != "" {
			tags["launch_database_cluster"] = a.ClusterName
		}
		a.stats.Distribution(ctx, "mysql_conn_open", tags, float64(info.OpenConnections))
		a.stats.Distribution(ctx, "mysql_conn_inuse", tags, float64(info.InUse))
		a.stats.Distribution(ctx, "mysql_conn_idle", tags, float64(info.Idle))
		a.stats.Distribution(ctx, "mysql_conn_wait", tags, float64(info.WaitCount))
		a.stats.Distribution(ctx, "mysql_conn_wait_ms", tags, float64(info.WaitDuration.Milliseconds()))
		a.stats.Distribution(ctx, "mysql_conn_max_idle_closed", tags, float64(info.MaxIdleClosed))
		a.stats.Distribution(ctx, "mysql_conn_lifetime_closed", tags, float64(info.MaxLifetimeClosed))
	}()

	if !a.breaker.Ready() {
		return tracing.RecordError(span, errs.Wrap(circuit.ErrBreakerOpen, "act_query"))
	}

	start := time.Now()

	// Annotate query
	annotations := append([]annotation.AnnotationOption{
		annotation.Name(operationName),
	}, a.annotations...)
	query = queryannotations.Annotate(
		ctx,
		query,
		queryannotations.WithFormatter(a.annotationsFormatter),
		queryannotations.WithPrepend(),
		queryannotations.WithAnnotations(annotations...),
	)

	err := fn(query)

	unexpectedError := err != nil && err != sql.ErrNoRows

	tags := statter.Tags{
		metrickeys.OperationName: operationName,
	}

	if unexpectedError {
		a.breaker.Fail()
		a.stats.Timing(ctx, "act_query.time", observability.ErrorTag(tags, err), time.Since(start))
		a.logger.Error(ctx, "act_query", kvp.String(metrickeys.OperationName, operationName), kvp.Duration("gh.launch.duration_sec", time.Since(start)), kvp.Err(err))
	} else {
		a.breaker.Success()
		a.stats.Timing(ctx, "act_query.time", tags, time.Since(start))
		a.logger.Debug(ctx, "act_query", kvp.String(metrickeys.OperationName, operationName), kvp.Duration("gh.launch.duration_sec", time.Since(start)))
	}

	callcounter.ExternalCall(ctx, "asql")

	return tracing.RecordError(span, err)
}

func configFromOptions(options Options) *config {
	cfg := &config{}
	if options != nil {
		options(cfg)
	}
	return cfg
}

type Namer interface {
	OperationName() string
}

type config struct {
	namer Namer
}

func (c *config) opName() string {
	if c.namer == nil {
		return "act_query_unknown"
	}
	return c.namer.OperationName()
}

// Options is a function to configure how a query is run - use With(...)
// to combine multiple options functions in left-to-right order
type Options func(*config)

func WithName(name string) Options {
	return func(c *config) {
		c.namer = staticName(name)
	}
}

type staticName string

func (s staticName) OperationName() string {
	return string(s)
}

// With combines options functions, when you wish to pass multiple options wrap them with `With`. They'll
// be applied left to right
func With(opts ...Options) Options {
	return func(c *config) {
		for _, fn := range opts {
			fn(c)
		}
	}
}

func (a *SQL) Conn() *sql.DB {
	return a.db
}
