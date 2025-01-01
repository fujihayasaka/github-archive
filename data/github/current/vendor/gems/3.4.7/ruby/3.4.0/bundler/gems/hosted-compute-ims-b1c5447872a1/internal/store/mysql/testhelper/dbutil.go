package testhelper

import (
	"context"
	"fmt"

	"github.com/github/hosted-compute-ims/internal/store/mysql"
	"github.com/github/hosted-compute-ims/internal/utils"
	"github.com/jmoiron/sqlx"
)

type DatabaseSuite struct {
	db     mysql.DB
	config mysql.Config
}

func (suite *DatabaseSuite) DB() mysql.DB {
	if suite.db.Write == nil {
		panic("Suite DB not initialized. Make sure it is set up in a Setup* function")
	}

	return suite.db
}

func (suite *DatabaseSuite) Config() *mysql.Config {
	return &suite.config
}

func (suite *DatabaseSuite) SetupDB() {
	suite.db, suite.config = PrepareTestDB(context.Background())
}

func (suite *DatabaseSuite) SetupSuite() {
	suite.SetupDB()
}

func (suite *DatabaseSuite) TearDownDB() {
	if suite.db.Write == nil {
		return
	}

	ctx := context.Background()
	if err := TruncateAllTables(ctx, suite.db); err != nil {
		panic(fmt.Sprintf("truncate test db: %s", err))
	}

	suite.db.Write.Close()
}

func (suite *DatabaseSuite) TearDownSuite() {
	suite.TearDownDB()
}

// Prepares a clean test database, and returns the read/write connections
func PrepareTestDB(ctx context.Context) (mysql.DB, mysql.Config) {
	config := mysql.Config{}

	err := config.Load()
	if err != nil {
		panic(fmt.Sprintf("prepare test db: %s", err))
	}

	// override mysql database to not mix data with development
	config.DatabaseName = "hosted_compute_ims_test"
	// override mysql host to use development instance
	config.Host, err = utils.GetMinikubeIp()
	if err != nil {
		panic(fmt.Sprintf("getting mysql host: %s", err))
	}

	dbWriteURL, err := config.DatabaseWriteURL()
	if err != nil {
		panic(fmt.Sprintf("prepare test db: %s", err))
	}

	dbWrite, err := sqlx.ConnectContext(ctx, "mysql", dbWriteURL)
	if err != nil {
		panic(fmt.Sprintf("prepare test db: %s", err))
	}

	dbReadURL, err := config.DatabaseReadURL()
	if err != nil {
		panic(fmt.Sprintf("prepare test db: %s", err))
	}

	dbRead, err := sqlx.ConnectContext(ctx, "mysql", dbReadURL)
	if err != nil {
		panic(fmt.Sprintf("prepare test db: %s", err))
	}

	db := mysql.DB{
		Write: dbWrite,
		Read:  dbRead,
	}

	err = TruncateAllTables(ctx, db)
	if err != nil {
		panic(fmt.Sprintf("prepare test db: %s", err))
	}

	return db, config
}

func CloseDB(db mysql.DB) {
	db.Write.Close()
	db.Read.Close()
}

func TruncateAllTables(ctx context.Context, db mysql.DB) error {
	rows, err := db.Write.QueryContext(ctx, "show tables")
	if err != nil {
		return err
	}

	var allTables []string
	for rows.Next() {
		var tableName string

		err := rows.Scan(&tableName)
		if err != nil {
			return err
		}

		allTables = append(allTables, tableName)
	}
	rows.Close()

	if err = TruncateTables(ctx, db, allTables); err != nil {
		return err
	}

	return nil
}

func TruncateTables(ctx context.Context, db mysql.DB, tables []string) error {
	var dbName string

	err := db.Write.GetContext(ctx, &dbName, "select database()")
	if err != nil {
		return err
	}

	if dbName != "hosted_compute_ims_test" {
		panic(fmt.Sprintf("TruncateTables is expected to be called on the hosted_compute_ims_test database, but it is actually being called on: %s", dbName))
	}

	for _, tableName := range tables {
		_, err = db.Write.ExecContext(ctx, fmt.Sprintf("truncate %s", tableName))
		if err != nil {
			return err
		}
	}

	return nil
}
