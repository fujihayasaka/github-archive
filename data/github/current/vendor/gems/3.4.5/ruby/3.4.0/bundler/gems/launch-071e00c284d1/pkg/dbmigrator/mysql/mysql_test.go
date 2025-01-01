package mysql

import (
	"context"
	"database/sql"
	"fmt"
	"os"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/github/launch/mysqldb"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/pkg/dbmigrator"
)

const testMigrationsTable = "test_schema_migrations"
const testMigrationsDirectory = "file://testdata"

func TestNew(t *testing.T) {
	dbURL := fmt.Sprintf("mysql://%s", os.Getenv("LAUNCH_DEPLOYER_TEST_DATABASE_URL"))

	tests := []struct {
		desc                string
		errExpected         bool
		migrationsDirectory bool
		expectedVersion     map[string]uint
		sourceURL           string
		databaseURL         string
		migrationsTable     string
	}{
		{
			desc:            "returns no error when database exists",
			errExpected:     false,
			databaseURL:     dbURL,
			sourceURL:       testMigrationsDirectory,
			migrationsTable: testMigrationsTable,
		},
		{
			desc:            "returns error for invalid database URL",
			errExpected:     true,
			databaseURL:     "",
			sourceURL:       testMigrationsDirectory,
			migrationsTable: testMigrationsTable,
		},
		{
			desc:            "returns an error when trying to use `schema_migrations` as the table name",
			errExpected:     true,
			databaseURL:     dbURL,
			sourceURL:       testMigrationsDirectory,
			migrationsTable: "schema_migrations",
		},
		{
			desc:            "returns an error for blank source URL",
			errExpected:     true,
			databaseURL:     dbURL,
			sourceURL:       "",
			migrationsTable: testMigrationsTable,
		},
	}

	for _, tt := range tests {
		t.Run(tt.desc, func(t *testing.T) {
			_, err := New(tt.sourceURL, tt.databaseURL, tt.migrationsTable)
			if tt.errExpected {
				assert.Error(t, err, "should have return an error")
			} else {
				require.NoError(t, err)
			}
		})
	}
}

func TestMigrate(t *testing.T) {
	dbURL := fmt.Sprintf("mysql://%s", os.Getenv("LAUNCH_DEPLOYER_TEST_DATABASE_URL"))

	tests := []struct {
		desc         string
		errExpected  bool
		transitionFn func(*testing.T, *sql.DB, *dbmigrator.Transitioner) error
		assertFn     func(*testing.T, *sql.DB, *Migrator) error
	}{
		{
			desc:        "successfully runs migrations for the initial migration",
			errExpected: false,
			assertFn: func(t *testing.T, db *sql.DB, m *Migrator) error {
				v, _, err := m.migrate.Version()
				require.NoError(t, err)
				assert.Equal(t, v, uint(20200217180540)) // Should migrate all the way to the end.
				return nil
			},
		},
		{
			desc:        "successfully runs transitions during migrations",
			errExpected: false,
			transitionFn: func(t *testing.T, db *sql.DB, ts *dbmigrator.Transitioner) error {
				err := ts.Add(20200217180026, func(ctx context.Context) error {
					_, err := db.ExecContext(ctx, `INSERT INTO test_table SET body="testbody"`)
					require.NoError(t, err)

					return nil
				})
				require.NoError(t, err)

				// For after the last migration is applied, let's do a pseudo-backfill.
				err = ts.Add(20200217180540, func(ctx context.Context) error {
					_, err := db.ExecContext(ctx, `UPDATE test_table SET body_copy=body;`)
					require.NoError(t, err)

					return nil
				})
				require.NoError(t, err)

				return nil
			},
			assertFn: func(t *testing.T, db *sql.DB, m *Migrator) error {
				var bodyString string
				err := db.QueryRowContext(context.TODO(), `SELECT body from test_table LIMIT 1;`).Scan(&bodyString)
				require.NoError(t, err)
				assert.Equal(t, bodyString, "testbody")

				var bodyCopy string
				err = db.QueryRowContext(context.TODO(), `SELECT body_copy from test_table LIMIT 1;`).Scan(&bodyCopy)
				require.NoError(t, err)
				assert.Equal(t, bodyCopy, "testbody")

				return nil
			},
		},
		{
			desc:        "throws an error for duplicate transitions",
			errExpected: false,
			transitionFn: func(t *testing.T, db *sql.DB, ts *dbmigrator.Transitioner) error {
				err := ts.Add(20200217180026, func(ctx context.Context) error {
					_, err := db.ExecContext(ctx, `INSERT INTO test_table SET body="testbody"`)
					require.NoError(t, err)

					return nil
				})
				require.NoError(t, err)

				err = ts.Add(20200217180026, func(ctx context.Context) error {
					return nil
				})
				assert.Error(t, err, "should return an error for duplicate transitiions")

				return nil
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.desc, func(t *testing.T) {
			conn, err := mysqldb.NewDB(statter.NullStatter(), os.Getenv("LAUNCH_DEPLOYER_TEST_DATABASE_URL"))
			require.NoError(t, err)
			defer conn.Close()

			// Cleanup previous runs and executions
			_, err = conn.Exec("DROP TABLE IF EXISTS test_schema_migrations")
			require.NoError(t, err)
			_, err = conn.Exec("DROP TABLE IF EXISTS test_table")
			require.NoError(t, err)

			ts := dbmigrator.NewTransitioner()
			m, err := New(testMigrationsDirectory, dbURL, testMigrationsTable)
			require.NoError(t, err)

			if tt.transitionFn != nil {
				err = tt.transitionFn(t, conn, ts)
				require.NoError(t, err)
			}

			err = m.Migrate(context.TODO(), ts)
			if tt.errExpected {
				require.Error(t, err, "Migrate should have returned an error")
			} else {
				require.NoError(t, err, "Migrate should not have returned an error")
			}

			if tt.assertFn != nil {
				err = tt.assertFn(t, conn, m)
				require.NoError(t, err)
			}
		})
	}
}
