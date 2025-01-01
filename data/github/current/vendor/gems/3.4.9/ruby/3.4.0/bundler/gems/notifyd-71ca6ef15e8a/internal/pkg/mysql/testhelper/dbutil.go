// Package testhelper implements test helpers for the mysql package.
package testhelper

import (
	"context"
	"fmt"

	ghconfig "github.com/github/go-config"

	"github.com/github/notifyd/internal/pkg/config"
	"github.com/github/notifyd/internal/pkg/mysql"
)

/*
DatabaseSuite builds test suites that have a dependency on the database.
This struct will:
* Initialize a new DB connection on suite setup
* Initialize a new SequentialIDs instance to use sequential IDs in the tests
* Truncate all tables on suite tear down and close the DB connection

You can use this suite with your own by embedding it:

	import (
		"github.com/stretchr/testify/suite"
		"github.com/github/notifyd/internal/pkg/mysql/testhelper"
	)

	type MyTestSuite struct {
		suite.Suite
		testhelper.DatabaseSuite
	}

By default this struct defines the functions SetupSuite() and TearDownSuite(),
but you can define your own. You'll need to make sure you call the Setup* and
TearDown* methods for the db and seqIDs instances:

	import (
		"github.com/stretchr/testify/suite"
		"github.com/github/notifyd/internal/pkg/mysql/testhelper"
	)

	type MyTestSuite struct {
		suite.Suite
		testhelper.DatabaseSuite
	}

	func (s *MyTestSuite) SetupSuite() {
		s.SetupDB()
		s.SetupSequentialIDs()
		// your own logic
	}

	func (s *MyTestSuite) TearDownSuite() {
		s.TearDownDB()
		// your own logic
	}
*/
type DatabaseSuite struct {
	db        mysql.DB
	dbCleanup func()
	seqIDs    *SequentialIDs
}

// DB returns the database connection.
func (suite *DatabaseSuite) DB() mysql.DB {
	if suite.db.Write == nil || suite.db.Read == nil {
		panic("Suite DB not initialized. Make sure it is set up in a Setup* function")
	}

	return suite.db
}

// SequentialIDs returns the sequential IDs instance.
func (suite *DatabaseSuite) SequentialIDs() *SequentialIDs {
	if suite.seqIDs == nil {
		panic("Suite SequentialIDs not initialized. Make sure it is set up in a Setup* function")
	}

	return suite.seqIDs
}

// SetupDB initializes the database connection.
func (suite *DatabaseSuite) SetupDB() {
	suite.db, suite.dbCleanup = PrepareTestDB(context.Background())
}

// SetupSequentialIDs initializes the sequential IDs instance.
func (suite *DatabaseSuite) SetupSequentialIDs() {
	suite.seqIDs = NewSequentialIDs()
}

// SetupSuite initializes the database suite.
func (suite *DatabaseSuite) SetupSuite() {
	suite.SetupDB()
	suite.SetupSequentialIDs()
}

// TearDownDB truncates all tables and closes the database connection.
func (suite *DatabaseSuite) TearDownDB() {
	if suite.db.Write == nil {
		return
	}

	ctx := context.Background()
	if err := TruncateAllTables(ctx, suite.db); err != nil {
		panic(fmt.Sprintf("truncate test db: %s", err))
	}

	suite.dbCleanup()
}

// TearDownSuite tears down the database suite.
func (suite *DatabaseSuite) TearDownSuite() {
	suite.TearDownDB()
}

// Config represents the configuration for the database.
type Config struct {
	Environment string `config:",env=APP_ENV"`
	Database    mysql.Config
}

// PrepareTestDB prepares a clean test database, and returns the read/write connections
func PrepareTestDB(ctx context.Context) (mysql.DB, func()) {
	config.LoadDotEnv()
	cfg := Config{Environment: "development"}
	if err := ghconfig.Load(&cfg); err != nil {
		panic(fmt.Sprintf("prepare test db: %s", err))
	}
	if cfg.Environment != "test" {
		panic(fmt.Sprintf("APP_ENV must be set to test, is set to %s", cfg.Environment))
	}

	db, dbCleanup, err := mysql.New(ctx, cfg.Database, cfg.Environment)
	if err != nil {
		panic(fmt.Sprintf("prepare test db: %s", err))
	}

	err = TruncateAllTables(ctx, db)
	if err != nil {
		panic(fmt.Sprintf("prepare test db: %s", err))
	}

	return db, func() { _ = dbCleanup() }
}

// TruncateAllTables truncates all tables in the test database.
func TruncateAllTables(ctx context.Context, db mysql.DB) error {
	var dbName string
	err := db.Write.GetContext(ctx, &dbName, "select database()")
	if err != nil {
		return err
	}

	if dbName != "notifyd_test" {
		panic(fmt.Sprintf("TruncateAllTables called on %s not notifyd_test", dbName))
	}

	rows, err := db.Write.QueryContext(ctx, "show tables")
	if err != nil {
		return err
	}
	defer rows.Close()

	for rows.Next() {
		var tableName string
		err := rows.Scan(&tableName)
		if err != nil {
			return err
		}

		// We don't want to truncate the migrations table. That table tells us the
		// last migration that was run and if we truncate it we won't be able to run
		// migrations on the test table.
		if tableName == "notifyd_schema_migrations" {
			continue
		}

		_, err = db.Write.ExecContext(ctx, fmt.Sprintf("truncate %s", tableName))
		if err != nil {
			return err
		}
	}
	return nil
}

// TruncateTables truncates the given tables in the test database.
func TruncateTables(ctx context.Context, db mysql.DB, tables []string) error {
	var dbName string
	err := db.Write.GetContext(ctx, &dbName, "select database()")
	if err != nil {
		return err
	}

	if dbName != "notifyd_test" {
		panic(fmt.Sprintf("TruncateTables called on %s not notifyd_test", dbName))
	}

	for _, tableName := range tables {
		// We don't want to truncate the migrations table. That table tells us the
		// last migration that was run and if we truncate it we won't be able to run
		// migrations on the test table.
		if tableName == "notifyd_schema_migrations" {
			continue
		}

		_, err = db.Write.ExecContext(ctx, fmt.Sprintf("truncate %s", tableName))
		if err != nil {
			return err
		}
	}
	return nil
}
