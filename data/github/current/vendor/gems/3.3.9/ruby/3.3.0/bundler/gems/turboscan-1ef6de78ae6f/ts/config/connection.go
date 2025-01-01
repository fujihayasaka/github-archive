package config

import (
	"context"
	"database/sql"
	"database/sql/driver"
	"time"

	"github.com/github/turboscan/ts/mysql/resilientdb"
	"github.com/github/turboscan/ts/o11y"

	"github.com/github/github-telemetry-go/log"
	"github.com/pkg/errors"

	"github.com/github/go-stats"
	"github.com/jinzhu/gorm"

	"github.com/go-sql-driver/mysql"
)

// Open a connection to the cluster defined by the input configuration
func Open(cfg *mysql.Config, logger log.Logger, statter stats.Client) (*gorm.DB, error) {
	conn, err := mysql.NewConnector(cfg)
	if err != nil {
		return nil, err
	}

	conn = wrapConnector(conn, logger, statter)

	return gorm.Open("mysql", resilientdb.NewDB(sql.OpenDB(conn), logger, statter))
}

type metricsConnector struct {
	connector driver.Connector
	log       log.Logger
	st        stats.Client
}

func (m *metricsConnector) Connect(ctx context.Context) (driver.Conn, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	m.st.Counter("mysql.conn_open", nil, 1)
	startTime := time.Now()
	conn, err := m.connector.Connect(ctx)
	m.st.DistributionMs("mysql.conn_time", nil, time.Since(startTime))
	if err != nil {
		m.st.Counter("mysql.conn_err", nil, 1)
		m.log.WithError(err).Error("failed to open mysql connection")
		return nil, errors.Wrap(err, "failed to open connection to mysql")
	}
	return conn, nil
}

func (m *metricsConnector) Driver() driver.Driver {
	return m.connector.Driver()
}

func wrapConnector(c driver.Connector, logger log.Logger, statter stats.Client) driver.Connector {
	return &metricsConnector{
		st:        statter,
		connector: c,
		log:       logger,
	}
}
