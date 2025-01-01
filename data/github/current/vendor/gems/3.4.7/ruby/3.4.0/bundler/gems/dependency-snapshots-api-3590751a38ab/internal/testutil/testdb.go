package testutil

import (
	"context"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"testing"

	"github.com/github/dependency-snapshots-api/internal/config"
	"github.com/github/dependency-snapshots-api/internal/db"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	"github.com/stretchr/testify/require"
	"golang.org/x/sync/errgroup"
)

var loadTables sync.Once
var tables = make(map[string]string)

// var _ Config = &TestDB{}
var _ io.Closer = &TestDB{}

type TestDB struct {
	t       *testing.T
	DB      *db.DB
	DBName  string
	config  *config.Config
	logger  log.Logger
	statter stats.Client
}

func (tdb *TestDB) ensureDatabase() error {
	dbConfig := tdb.config.NewMysqlConfig()
	dbConfig.DBName = ""

	// This is necessary because Open registers drivers
	temporaryDB, err := db.ConnectToMysql(context.Background(), dbConfig, 1, 1)
	if err != nil {
		return err
	}

	if err := db.MysqlDropSchema(temporaryDB, tdb.DBName); err != nil {
		return err
	}
	if err := db.MysqlCreateSchema(temporaryDB, tdb.DBName); err != nil {
		return err
	}

	if err = temporaryDB.Close(); err != nil {
		return err
	}

	return nil
}

// nolint
func NewNamedTestDB(t *testing.T, cfg *config.Config, logger log.Logger, statter stats.Client, dbName string) (*TestDB, error) {
	testDB := &TestDB{
		t:       t,
		config:  cfg,
		DBName:  dbName,
		logger:  logger,
		statter: statter,
	}

	require.NoError(t, testDB.ensureDatabase())

	_, b, _, _ := runtime.Caller(0)
	basepath := filepath.Dir(b)
	schemasPath := fmt.Sprintf("%s/../../schemas/", basepath)

	var err error
	loadTables.Do(func() {
		var files []os.DirEntry
		if files, err = os.ReadDir(schemasPath); err != nil {
			err = fmt.Errorf("couldn't find schemas folder at the expected location (%s): %w", schemasPath, err)
			return
		}

		for _, file := range files {
			if strings.HasSuffix(file.Name(), ".sql") {
				var b []byte
				if b, err = os.ReadFile(fmt.Sprintf("%s/%s", schemasPath, file.Name())); err != nil {
					return
				}
				tables[strings.TrimSuffix(file.Name(), ".sql")] = string(b)
			}
		}
	})
	if err != nil {
		return nil, err
	}
	cfg.DB = dbName
	if testDB.DB, err = db.GetMysqlDB(context.Background(), cfg, logger, statter); err != nil {
		return nil, err
	}

	if err = testDB.ApplySchemas(); err != nil {
		return nil, err
	}

	return testDB, nil
}

func (tdb *TestDB) ApplySchemas() error {
	var eg errgroup.Group
	eg.SetLimit(5)
	for table, tableSchema := range tables {
		// copy from loop var
		tbl := table
		schema := tableSchema
		eg.Go(func() error {
			if _, err := tdb.DB.PrimaryExecutor.ExecContext(context.Background(), schema); err != nil {
				return fmt.Errorf("couldn't create table %s: %w", tbl, err)
			}
			return nil
		})
	}
	return eg.Wait()
}

// ResetTables truncates tables and resets any auto_increment to zero
// For testing purposes, it is significantly slower than DeleteTables
func (tdb *TestDB) ResetTables(ignored ...string) error {
	var eg errgroup.Group
	eg.SetLimit(30)
	ignoredMap := make(map[string]struct{})
	for _, s := range ignored {
		ignoredMap[s] = struct{}{}
	}

	for table := range tables {
		if _, ok := ignoredMap[table]; ok {
			continue
		}
		// copy from loop var
		tbl := table
		eg.Go(func() error {
			if _, err := tdb.DB.PrimaryExecutor.ExecContext(context.Background(), fmt.Sprintf("TRUNCATE TABLE %s", tbl)); err != nil {
				return fmt.Errorf("couldn't truncate table %s: %w", tbl, err)
			}
			return nil
		})
	}
	return eg.Wait()
}

// DeleteTables is faster than ResetTables _in test environments_ because the tables are usually small, and truncating tables requires
// more global locks than deleting tables.
func (tdb *TestDB) DeleteTables(ignored ...string) error {
	var eg errgroup.Group
	eg.SetLimit(30)
	ignoredMap := make(map[string]struct{})
	for _, s := range ignored {
		ignoredMap[s] = struct{}{}
	}

	for table := range tables {
		if _, ok := ignoredMap[table]; ok {
			continue
		}
		// copy from loop var
		tbl := table
		eg.Go(func() error {
			if _, err := tdb.DB.PrimaryExecutor.ExecContext(context.Background(), fmt.Sprintf("DELETE FROM %s", tbl)); err != nil {
				return fmt.Errorf("couldn't delete from table %s: %w", tbl, err)
			}
			return nil
		})
	}
	return eg.Wait()
}

func (tdb *TestDB) Close() error {
	if _, err := tdb.DB.PrimaryExecutor.ExecContext(context.Background(), fmt.Sprintf("DROP DATABASE IF EXISTS %s;", tdb.DBName)); err != nil {
		require.NoError(tdb.t, err)
		return err
	}

	require.NoError(tdb.t, tdb.DB.Close())

	return nil
}
