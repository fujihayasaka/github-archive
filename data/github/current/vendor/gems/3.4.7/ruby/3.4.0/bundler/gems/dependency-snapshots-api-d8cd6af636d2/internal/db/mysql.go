package db

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"sync"
	"time"

	"github.com/XSAM/otelsql"
	"github.com/github/dependency-snapshots-api/internal/config"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	"github.com/go-sql-driver/mysql"
	semconv "go.opentelemetry.io/otel/semconv/v1.18.0"
)

func GetMysqlDB(ctx context.Context, cfg *config.Config, logger log.Logger, statter stats.Client) (*DB, error) {
	if !cfg.IsProduction() {
		//non-prod environments only have a single DB connection, so there's no reason to open multiple connections
		db, err := ConnectToMysql(ctx, cfg.NewMysqlConfig(), cfg.DBIdleConnections, cfg.DBMaxConnections)
		if err != nil {
			return nil, err
		}
		return &DB{
			PrimaryExecutor: db,
			ReplicaExecutor: db,
			statter:         statter,
			logger:          logger,
			primary:         db,
			replica:         db,
		}, nil
	}

	// Production is vitess and has explicit keyspace aliases for the primary vs read replica
	primaryCfg := cfg.NewMysqlConfig()
	primaryCfg.DBName += "@master"
	primaryDB, err := ConnectToMysql(ctx, primaryCfg, cfg.DBIdleConnections, cfg.DBMaxConnections)
	if err != nil {
		return nil, err
	}

	replicaCfg := cfg.NewMysqlConfig()
	replicaCfg.DBName += "@replica"
	replicaDB, err := ConnectToMysql(ctx, replicaCfg, cfg.DBIdleConnections, cfg.DBMaxConnections)
	if err != nil {
		return nil, err
	}

	out := &DB{
		PrimaryExecutor: primaryDB,
		ReplicaExecutor: replicaDB,
		statter:         statter,
		logger:          logger,
		primary:         primaryDB,
		replica:         replicaDB,
	}
	return out, nil
}

func ConnectToMysql(ctx context.Context, mysqlCfg *mysql.Config, maxIdleConnections, maxConnections int) (*sql.DB, error) {
	dsn := mysqlCfg.FormatDSN()
	driver, err := GetOtelMysqlDriverName()
	if err != nil {
		return nil, err
	}
	db, err := sql.Open(driver, dsn)
	if err != nil {
		return nil, err
	}

	if err := db.PingContext(ctx); err != nil {
		return nil, err
	}

	// Timeouts following https://github.com/github/go/blob/main/docs/database_access.md#setting-connection-timeouts
	// MaxIdleTime must be set first per https://github.com/golang/go/issues/45993
	db.SetConnMaxIdleTime(25 * time.Second)
	db.SetConnMaxLifetime(time.Minute)
	db.SetMaxIdleConns(maxIdleConnections)
	db.SetMaxOpenConns(maxConnections)

	return db, nil
}

var registerMysqlOtelDriverOnce sync.Once
var otelMysqlDriverName string

func GetOtelMysqlDriverName() (string, error) {
	var err error
	registerMysqlOtelDriverOnce.Do(func() {
		otelMysqlDriverName, err = otelsql.Register("mysql", otelsql.WithAttributes(
			semconv.DBSystemMySQL,
		))
	})
	return otelMysqlDriverName, err
}

func IsMysqlDeadlockError(err error) bool {
	// Error number: 1213; Symbol: ER_LOCK_DEADLOCK; SQLSTATE: 40001
	// https://dev.mysql.com/doc/mysql-errors/8.0/en/server-error-reference.html#error_er_lock_deadlock
	return isMysqlErrorNum(err, 1213)
}

func IsMysqlRecordNotUnique(err error) bool {
	// Error number: 1062; Symbol: ER_DUP_ENTRY; SQLSTATE: 23000
	// https://dev.mysql.com/doc/mysql-errors/8.0/en/server-error-reference.html#error_er_dup_entry
	return isMysqlErrorNum(err, 1062)
}

func IsMysqlQueryInterrupted(err error) bool {
	// Error number: 1317; Symbol: ER_QUERY_INTERRUPTED; SQLSTATE: 70100
	// https://dev.mysql.com/doc/mysql-errors/8.0/en/server-error-reference.html#error_er_query_interrupted
	return isMysqlErrorNum(err, 1317)
}

func isMysqlErrorNum(err error, errNum uint16) bool {
	if err == nil {
		return false
	}
	var mysqlError *mysql.MySQLError
	return errors.As(err, &mysqlError) && mysqlError.Number == errNum
}

func MysqlDropSchema(db *sql.DB, schemaName string) error {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	stmt := fmt.Sprintf("DROP DATABASE IF EXISTS %s", schemaName)
	_, err := db.ExecContext(ctx, stmt)
	return err
}

func MysqlCreateSchema(db *sql.DB, schemaName string) error {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	exists, err := doesSchemaExist(ctx, db, schemaName)
	if err != nil {
		return err
	}

	if !exists {
		stmt := fmt.Sprintf("CREATE DATABASE %s CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_520_ci;", schemaName)
		_, err := db.ExecContext(ctx, stmt)
		return err
	}

	return nil
}

func doesSchemaExist(ctx context.Context, db *sql.DB, schemaName string) (bool, error) {
	var result string
	stmt := "SELECT SCHEMA_NAME FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME = ?"
	err := db.QueryRowContext(ctx, stmt, schemaName).Scan(&result)
	if err != nil {
		if err == sql.ErrNoRows {
			return false, nil
		} else {
			return false, err
		}
	}
	return true, nil
}
