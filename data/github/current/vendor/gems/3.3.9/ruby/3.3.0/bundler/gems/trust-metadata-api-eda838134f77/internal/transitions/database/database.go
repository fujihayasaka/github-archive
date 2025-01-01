package database

import (
	"fmt"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/jmoiron/sqlx"
	"github.com/pkg/errors"
)

const mySQLDBConnFormat = "%s:%s@tcp(%s:%s)/%s?parseTime=true"

type DBConn struct {
	MySQLHost     string
	MySQLDatabase string
	MySQLPassword string
	MySQLPort     string
	MySQLUser     string
}

type DBConfig struct {
	PrimaryDBConn   DBConn
	ROReplicaDBConn DBConn
}

func buildDBConnString(c DBConn) string {
	return fmt.Sprintf(mySQLDBConnFormat,
		c.MySQLUser,
		c.MySQLPassword,
		c.MySQLHost,
		c.MySQLPort,
		c.MySQLDatabase)
}

func BuildDBConn(c DBConfig, readOnly bool, logger log.Logger) (*sqlx.DB, error) {
	if readOnly {
		replicaDBConnString := buildDBConnString(c.ROReplicaDBConn)
		db, err := sqlx.Connect("mysql", replicaDBConnString)
		if err != nil {
			logger.Error("error connecting to mysql read only replica", kvp.Err(err))
			return nil, errors.Wrap(err, "error connecting to mysql read only replica")
		}
		return db, nil
	}

	primaryDBConnString := buildDBConnString(c.PrimaryDBConn)
	db, err := sqlx.Connect("mysql", primaryDBConnString)
	if err != nil {
		logger.Error("error connecting to mysql primary", kvp.Err(err))
		return nil, errors.Wrap(err, "error connecting to mysql primary")
	}

	return db, nil
}
