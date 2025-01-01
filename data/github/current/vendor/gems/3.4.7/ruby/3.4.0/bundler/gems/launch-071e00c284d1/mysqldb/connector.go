package mysqldb

import (
	"context"
	"database/sql/driver"
	"time"

	"github.com/go-sql-driver/mysql"
	"github.com/pkg/errors"

	"github.com/github/launch/observability/statter"
)

type retryingConnector struct {
	statter   statter.Statter
	cfg       *mysql.Config
	retries   int
	wait      time.Duration
	connector driver.Connector
}

func (rc *retryingConnector) Connect(ctx context.Context) (driver.Conn, error) {
	var err error

	for i := 0; i < rc.retries; i++ {
		var connection driver.Conn
		connection, err = rc.connector.Connect(ctx)
		if err != nil {
			rc.record(ctx, "false")
			time.Sleep(rc.wait)
			continue
		}

		rc.record(ctx, "true")
		return connection, nil
	}

	return nil, err
}

// Driver always returns the MySQL driver
func (rc *retryingConnector) Driver() driver.Driver {
	return &mysql.MySQLDriver{}
}

func (rc *retryingConnector) record(ctx context.Context, connected string) {
	rc.statter.Counter(ctx, "mysql_connection_attempt", map[string]string{
		"connected": connected,
	}, 1)
}

func NewRetryingConnector(statter statter.Statter, cfg *mysql.Config, retries int, wait time.Duration) (driver.Connector, error) {
	connector, err := mysql.NewConnector(cfg)
	if err != nil {
		return nil, errors.Wrap(err, "error creating connector")
	}

	return &retryingConnector{
		connector: connector,
		statter:   statter,
		cfg:       cfg,
		retries:   retries,
		wait:      wait,
	}, nil
}
