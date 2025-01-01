package db

import (
	"context"
	"database/sql/driver"
	"time"

	"github.com/github/authnd/internal/common/config"
	"github.com/github/authnd/internal/common/diagnostics"
	"github.com/github/authnd/internal/common/tracing"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-http/v2/middleware/requestid"
	"github.com/github/go-queryannotations"
	"github.com/github/go-queryannotations/annotatesql"
	"github.com/github/go-queryannotations/annotation"
	"github.com/github/go-stats"
	"github.com/go-sql-driver/mysql"
	"github.com/jmoiron/sqlx"
	"github.com/pkg/errors"
)

// Open opens a new database connection
func Open(logger log.Logger, dbCfg *config.DatabaseConfig) (*sqlx.DB, error) {
	logger.Info("opening new database connection",
		kvp.String("gh.authnd.db.name", dbCfg.MysqlConfig.DBName),
		kvp.String("gh.authnd.db.address", dbCfg.MysqlConfig.Addr),
		kvp.String("gh.authnd.db.user", dbCfg.MysqlConfig.User),
		kvp.Int("gh.authnd.db.max_open_conns", dbCfg.MaxOpenConns),
		kvp.Int("gh.authnd.db.max_idle_conns", dbCfg.MaxIdleConns),
		kvp.Duration("gh.authnd.db.max_idle_time", dbCfg.ConnMaxIdleTime),
		kvp.Duration("gh.authnd.db.max_idle_lifetime", dbCfg.ConnMaxLifetime),
	)

	conn, err := mysql.NewConnector(dbCfg.MysqlConfig)
	if err != nil {
		return nil, errors.WithStack(err)
	}

	conn = withMetrics(conn, stats.Tags{
		"db":         dbCfg.MysqlConfig.DBName,
		"connection": dbCfg.ConnectionName,
	}, []kvp.Field{
		kvp.String("db", dbCfg.MysqlConfig.DBName),
		kvp.String("connection", dbCfg.ConnectionName),
	})

	db := annotatesql.OpenDB(conn,
		queryannotations.WithPrepend(),
		queryannotations.WithAnnotations(
			annotation.Application("authnd"),
			func(ctx context.Context) *annotation.Annotation {
				requestID := requestid.GetGitHubRequestID(ctx)
				if requestID == "" {
					return nil
				}

				return &annotation.Annotation{
					Key:   annotation.RequestIDKey,
					Value: requestID,
				}
			},
		),
	)

	// See https://golang.org/pkg/database/sql/#DB.SetMaxOpenConns
	db.SetMaxOpenConns(dbCfg.MaxOpenConns)
	// See https://golang.org/pkg/database/sql/#DB.SetMaxIdleConns
	db.SetMaxIdleConns(dbCfg.MaxIdleConns)
	// See https://pkg.go.dev/database/sql#DB.SetConnMaxIdleTime
	db.SetConnMaxIdleTime(dbCfg.ConnMaxIdleTime)
	// See https://golang.org/pkg/database/sql/#DB.SetConnMaxLifetime
	db.SetConnMaxLifetime(dbCfg.ConnMaxLifetime)

	dbx := sqlx.NewDb(db, "mysql")

	return dbx, nil
}

type metricsConnector struct {
	conn   driver.Connector
	drv    driver.Driver
	tags   stats.Tags
	fields []kvp.Field
}

func (d *metricsConnector) Connect(ctx context.Context) (driver.Conn, error) {
	statter := diagnostics.Statter(ctx)
	logger := diagnostics.Logger(ctx)

	// Create a span specifically for the Connect
	// This _should_ mean the Connect will show up in a trace under the operation that caused a new connection to be established.
	ctx, span := tracing.ChildSpan(ctx, "mysql.Connect")
	defer span.End()

	statter.Counter("db.sql.opened", d.tags, 1)
	startTime := time.Now()
	conn, err := d.conn.Connect(ctx)
	statter.DistributionMs("db.sql.opened.time", d.tags, time.Since(startTime))
	if err != nil {
		// If the error is that the context is being cancelled (shutdown), just forward it along without logging/wrapping.
		if errors.Is(err, context.Canceled) {
			return nil, err
		}
		statter.Counter("db.sql.opened.error", d.tags, 1)
		logger.WithError(err).Error("failed to open mysql connection")
		return nil, errors.WithStack(err)
	}
	return conn, nil
}

func (d *metricsConnector) Driver() driver.Driver {
	return d.drv
}

func withMetrics(c driver.Connector, tags stats.Tags, fields []kvp.Field) driver.Connector {
	return &metricsConnector{
		conn:   c,
		drv:    c.Driver(),
		tags:   tags,
		fields: fields,
	}
}
