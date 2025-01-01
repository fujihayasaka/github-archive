// Package dbtest includes various helpers for interacting with the test database.
package dbtest

import (
	"database/sql"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/github/turboscan/ts"

	"github.com/SamuelTissot/sqltime"
	"github.com/github/turboscan/ts/mysql/resilientdb"
	"github.com/rogpeppe/go-internal/lockedfile"

	"github.com/go-sql-driver/mysql"
	"github.com/pkg/errors"

	"github.com/DATA-DOG/go-txdb"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	"github.com/jinzhu/gorm"
	"github.com/stretchr/testify/require"

	"github.com/github/turboscan/ts/config"
	"github.com/github/turboscan/ts/gormext"
)

var (
	// Logger is the github logger to use in tests. If you want to see SQL
	// queries run by GORM during tests change this to Logger = log.WithLevel(log.DebugLevel) and add
	// db.LogMode(true) to your test.
	Logger = log.NewNullLogger()

	// registerOnce is used to register the "txdb" driver once, even if we make
	// multiple calls to the functions using it
	registerOnce sync.Once
)

func addTestCallbacks(cb *gorm.Callback) {
	// vtgate error messages do not contain the query that caused them
	// add it on to make debugging Vitess issues easier
	cb.Query().After("gorm:query").Register("vitess:enhance_errors", func(scope *gorm.Scope) {
		if scope.HasError() {
			if strings.Contains(scope.DB().Error.Error(), "vtgate: ") {
				_ = scope.Err(errors.Errorf("incompatible query: %q", scope.SQL))
			}
		}
	})
}

// DeleteDB opens a test connection that is not suitable for parallel tests.
// Data will be committed to the database and deleted at the end of the run.
func DeleteDB(tb testing.TB, cfg *mysql.Config) *gorm.DB {
	tb.Helper()
	db, err := config.Open(cfg, Logger, stats.NullStatter)
	require.NoError(tb, err)

	var mutex sync.Mutex
	tables := make(map[string]struct{})

	beforeCreate := db.Callback().Create().Get("gorm:before_create")

	nullLogger := log.NewNullLogger()
	db.SetLogger(gormext.NewGormLogger(nullLogger))
	db.Callback().Create().Replace("gorm:before_create", func(scope *gorm.Scope) {
		beforeCreate(scope)
		mutex.Lock()
		tables[scope.QuotedTableName()] = struct{}{}
		mutex.Unlock()
	})
	db.SetLogger(gormext.NewGormLogger(Logger))

	tb.Cleanup(func() {
		for tableName := range tables {
			require.NoError(tb, db.Exec(`DELETE FROM `+tableName).Error)
		}
		require.NoError(tb, db.Close())
	})

	return db
}

func processLock(name string) func(tb testing.TB) {
	_, file, _, _ := runtime.Caller(0)
	path := filepath.Join(filepath.Clean(filepath.Join(filepath.Dir(file), "../..")), name)
	mutex := lockedfile.MutexAt(path)
	var locked bool

	return func(tb testing.TB) {
		tb.Helper()
		if locked {
			// keep track of the lock status to avoid tests deadlocking themselves by attempting to re-enter the same lock
			// this is not strictly necessary, however it makes using the lock safer
			return
		}
		unlock, err := mutex.Lock()
		require.NoError(tb, err)
		locked = true
		tb.Cleanup(func() {
			locked = false
			unlock()
		})
	}
}

var Mutex = processLock(".turboscan-test.lock")

// TxDB opens a connection that is suitable for sharded mode and parallel tests.
// The test is run in a transaction and rolled back at the end.
func TxDB(tb testing.TB, cfg *mysql.Config) *gorm.DB {
	tb.Helper()
	// we register an sql driver named "txdb" This is used to add
	// nested-transactions support (savepoints)
	registerOnce.Do(func() {
		txdb.Register("txdb", "mysql", cfg.FormatDSN())
	})

	tx, err := sql.Open("txdb", "test")
	require.NoError(tb, errors.Wrap(err, "unable to connect to test database: %w"))

	nullLogger := log.NewNullLogger()
	db, err := gorm.Open("mysql", resilientdb.NewDB(tx, nullLogger, stats.NullStatter))
	require.NoError(tb, err)

	tb.Cleanup(func() {
		require.NoError(tb, errors.Wrap(tx.Close(), "failed to rollback test db transaction: %w"))
	})

	return db
}

// requireConnection opens a connection to the database and configures gorm.
// the test will fail if a connection cannot be established.
func requireConnection(tb testing.TB, dbFn func(tb testing.TB, cfg *mysql.Config) *gorm.DB) *gorm.DB {
	tb.Helper()

	cfg, err := config.Load()
	if err != nil {
		tb.Fatal("unable to load config", err)
	}

	opts := &config.DBOptions{
		Config:            cfg,
		SkeemaEnvironment: "test",
	}
	dc, err := opts.DBConfig()
	if err != nil {
		tb.Fatal("unable to create a DB config", err)
	}

	Mutex(tb)

	db := dbFn(tb, dc)

	// Avoid spamming callback registration messages
	nullLogger := log.NewNullLogger()
	db.SetLogger(gormext.NewGormLogger(nullLogger))
	config.ConfigureGorm(db)
	addTestCallbacks(db.Callback())
	db.SetLogger(gormext.NewGormLogger(Logger))

	return db
}

// RequireConnectionWithoutTransaction opens a standard connection to the test database. If a connection
// cannot be opened then the current test is failed without returning. This can be useful if inspecting the database
// state while a test is running. Data will be deleted at the end of the test.
func RequireConnectionWithoutTransaction(tb testing.TB) *gorm.DB {
	tb.Helper()
	return requireConnection(tb, DeleteDB)
}

// RequireConnection uses TxDB to connect to the test database. If a connection
// cannot be opened then the current test is failed without returning. Transactions will be nested and the parent
// transaction will be rolled back at the end of the test.
func RequireConnection(tb testing.TB) *gorm.DB {
	tb.Helper()
	return requireConnection(tb, TxDB)
}

// RequireConnectionWithoutAutoIncrement returns a transaction-based connection that will set a deterministic ID
// for models when they are created. The transaction will be rolled back at the end of the test.
func RequireConnectionWithoutAutoIncrement(tb testing.TB) *gorm.DB {
	tb.Helper()

	db := RequireConnection(tb)

	var autoIncrement sync.Map

	beforeCreate := db.Callback().Create().Get("gorm:before_create")

	// Explicitly override the auto-incrementing primary key to ensure consistent test output.
	// This is effectively an in-memory autoincrement column scoped to each test run.
	nullLogger := log.NewNullLogger()
	db.SetLogger(gormext.NewGormLogger(nullLogger))
	db.Callback().Create().Replace("gorm:before_create", func(scope *gorm.Scope) {
		beforeCreate(scope)

		primaryField := scope.PrimaryField()

		if primaryField != nil && primaryField.IsBlank {
			var val atomic.Uint64
			addr, _ := autoIncrement.LoadOrStore(scope.TableName(), &val)
			actual, ok := addr.(*atomic.Uint64)
			require.True(tb, ok)
			next := actual.Add(1)
			require.NoError(tb, primaryField.Set(next))
		}
	})
	db.SetLogger(gormext.NewGormLogger(Logger))

	return db
}

func RequireConfiguration(tb testing.TB, db *gorm.DB, a *ts.Analysis) *ts.Analysis {
	tb.Helper()
	// in unit tests, prefer to create a Configuration on ts.Analysis automatically to save test writers
	// the trouble of calculating the categories in the test
	if a.ConfigurationID == 0 {
		cfg := &ts.Configuration{
			Ref:          a.Ref,
			RepositoryID: a.RepositoryID,
			ToolID:       a.ToolID,
			Category:     a.Category,
		}
		cfg.UpdateHash()
		require.NoError(tb, db.FirstOrCreate(cfg, ts.Configuration{RepositoryID: cfg.RepositoryID, Hash: cfg.Hash}).Error)
		a.ConfigurationID = cfg.ID
	}
	return a
}

// RequireCreate creates the given object in the DB and fails the test
// if the creation does not succeed.
func RequireCreate(tb testing.TB, db *gorm.DB, value any) {
	tb.Helper()
	if a, ok := value.(*ts.Analysis); ok {
		RequireConfiguration(tb, db, a)
	}
	err := db.Create(value).Error
	require.NoError(tb, err)
}

func RequireCreateIgnoreDuplicated(tb testing.TB, db *gorm.DB, value interface{}) {
	tb.Helper()
	if a, ok := value.(*ts.Analysis); ok {
		RequireConfiguration(tb, db, a)
	}
	err := db.Create(value).Error
	var mysqlErr *mysql.MySQLError
	if err != nil && errors.As(err, &mysqlErr) && mysqlErr.Number != 1062 {
		require.NoError(tb, err)
	}
}

// RequireCount runs Count on the given query and fails the test if
// the count does not match the expected count
func RequireCount(tb testing.TB, expected int, db *gorm.DB) {
	tb.Helper()
	var actual int
	err := db.Count(&actual).Error
	require.NoError(tb, err)
	require.Equal(tb, expected, actual)
}

// RequireUpdatedAt forcefully sets the `UpdatedAt` value for all
// rows matching the query
func RequireUpdatedAt(tb testing.TB, query *gorm.DB, timestamp time.Time) {
	tb.Helper()
	err := query.UpdateColumn("updated_at", sqltime.Time{Time: timestamp}).Error
	require.NoError(tb, err)
}

// FailingDB provides a means for creating a database connection
// that deterministically fails for certain queries.
type FailingDB struct {
	TargetErr      error             // Which error to throw
	TotalCount     uint32            // How many times to throw
	QueryPred      func(string) bool // Predicate to select queries to fail
	NonResilientDB bool              // Whether to use the normal DB instead of the resilientdb
}

type testDbInterface struct {
	*sql.DB

	FailingDB
	count atomic.Uint32 // How many times was the error thrown
}

func (db *testDbInterface) Query(query string, args ...interface{}) (*sql.Rows, error) {
	if db.QueryPred(query) && db.count.Add(1) <= db.TotalCount {
		return nil, db.TargetErr
	}
	return db.DB.Query(query, args...)
}

// BadConnection creates a connection around the failing DB
func BadConnection(failingDB FailingDB) func(tb testing.TB, cfg *mysql.Config) *gorm.DB {
	return func(tb testing.TB, cfg *mysql.Config) *gorm.DB {
		tb.Helper()
		// we register an sql driver named "txdb" This is used to add
		// nested-transactions support (savepoints)
		registerOnce.Do(func() {
			txdb.Register("txdb", "mysql", cfg.FormatDSN())
		})

		tx, err := sql.Open("txdb", "test")
		require.NoError(tb, errors.Wrap(err, "unable to connect to test database: %w"))

		nullLogger := log.NewNullLogger()
		tdb := &testDbInterface{DB: tx, FailingDB: failingDB}
		var conn resilientdb.Database = tdb
		if !failingDB.NonResilientDB {
			conn = resilientdb.NewDB(conn, nullLogger, stats.NullStatter)
		}
		db, err := gorm.Open("mysql", conn)
		require.NoError(tb, err)

		tb.Cleanup(func() {
			require.NoError(tb, errors.Wrap(tx.Close(), "failed to rollback test db transaction: %w"))
			// Assert that at least one error was thrown to prevent trivially succeeding tests
			require.Positive(tb, tdb.count.Load())
		})

		return db
	}
}

// RequireBadConnection returns a connection that will deterministically fail
// queries with an error specified in the failing DB.
func (f FailingDB) RequireBadConnection(tb testing.TB) *gorm.DB {
	tb.Helper()
	return requireConnection(tb, BadConnection(f))
}
