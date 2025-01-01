//go:build migrator
// +build migrator

// These tests exercise both migration and transition functionality.
//
// The tests in this file are tagged (and therefore not run by default) because
// they rely on executing "skeema" as a subprocess. They can be run reliably
// using `script/dev-run` inside Docker and are also run during CI.
//
// An example command for running a subset of these tests using `script/dev-run` is:
// go test -p 1 -race -tags migrator -run TestTransition ./ts/mysql/upgrades
package root

import (
	"context"
	"database/sql"
	"fmt"
	"io"
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/github/turboscan/ts/dbtest"
	"github.com/github/turboscan/ts/transforms"
	"golang.org/x/exp/constraints"

	"github.com/github/turboscan/ts/mysql/upgrades"

	"github.com/github/turboscan/migrations"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/turboscan/ts/config"
	"github.com/github/turboscan/ts/gormext"
	"github.com/stretchr/testify/require"
)

func createEmptyTestDatabase(t *testing.T, cfg *config.Config) {
	t.Helper()
	opts := &config.DBOptions{
		Config:            cfg,
		SkeemaEnvironment: "enterprisetest",
		IgnoreEnv:         true,
	}
	testConfig, err := opts.DBConfig()
	require.NoError(t, err)
	// database has not been created yet
	testConfig.DBName = ""
	testdb, err := sql.Open("mysql", testConfig.FormatDSN())
	require.NoError(t, err)

	t.Cleanup(func() {
		_, err = testdb.Exec("drop database if exists enterprise_test")
		require.NoError(t, err)
		err = testdb.Close()
		require.NoError(t, err)
	})

	_, err = testdb.Exec("drop database if exists enterprise_test")
	require.NoError(t, err)

	_, err = testdb.Exec("create database enterprise_test CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci")
	require.NoError(t, err)
}

func enterpriseTestDB(t *testing.T, opts *config.DBOptions) *sql.DB {
	t.Helper()
	db, err := config.OpenDB(opts, log.NewNullLogger(), nil)
	require.NoError(t, err)
	t.Cleanup(func() {
		err := db.Close()
		require.NoError(t, err)
	})
	return gormext.GetDB(db)
}

type testWriter struct {
	*testing.T
}

func (t testWriter) Write(v []byte) (int, error) {
	t.Log(strings.TrimSpace(string(v)))
	return len(v), nil
}

var _ io.Writer = testWriter{}

// This test executes the actual production GHES migrations and checks that the
// resulting database schema matches the state of the "schemas" directory, which
// in turn corresponds to the current state of the Cloud Turboscan database
// cluster schema.
func TestEnterpriseMigrations(t *testing.T) {
	cfg, err := config.Load()
	require.NoError(t, err)

	dbOpts := &config.DBOptions{
		IgnoreEnv: true,
		Config:    cfg,
		//SkeemaPath:        "",
		SkeemaEnvironment: "enterprisetest",
		MultiStatements:   true,
	}

	// Now that schema files have been upgraded for MySQL 8, running against MySQL 5
	// gives spurious diffs that are meaningless, so we can skip this test for MySQL 5
	// and rely on the MySQL 8 build.
	createEmptyTestDatabase(t, dbOpts.Config)
	db := enterpriseTestDB(t, dbOpts)

	row := db.QueryRow("SELECT VERSION()")
	var version string

	require.NoError(t, row.Scan(&version))

	if strings.HasPrefix(version, "5.") {
		t.Skip("skipping test for MySQL 5")
		return
	}

	upgradeEnv := upgrades.NewEnv("../../../migrations", enterpriseTestDB(t, dbOpts), MigrationsTable)

	transitions, err := migrations.Transitions.Build(upgradeEnv, &upgrades.Opts{})
	require.NoError(t, err)

	require.NoError(t, upgradeEnv.RunMigrations(context.Background(), transitions))

	t.Log("skeema", "diff", "--allow-unsafe", "--ignore-table", MigrationsTable, dbOpts.EffectiveSkeemaEnvironment())
	t.Log(dbOpts.EffectiveSkeemaPath())
	cmd := exec.Command("skeema", "diff", "--allow-unsafe", "--ignore-table", MigrationsTable, dbOpts.EffectiveSkeemaEnvironment())
	cmd.Dir = filepath.Dir(dbOpts.EffectiveSkeemaPath())
	output, err := cmd.CombinedOutput()
	t.Log(string(output))
	require.NoError(t, err, string(output))
}

func max[V constraints.Ordered](items []V) V {
	var found V
	for _, item := range items {
		if item > found {
			found = item
		}
	}
	return found
}

// latestCloudTransition returns true if the newest transition does not have a corresponding GHES migration
// and is more recent than the last migration.
// This should pick up the most recent transition that has been written for cloud or proxima.
func latestCloudTransition(t *testing.T) (uint, bool) {
	t.Helper()
	versionFromFile := func(s string) uint {
		var head uint
		var tail string
		_, err := fmt.Sscanf(s, "%d_%s", &head, &tail)
		require.NoError(t, err)
		require.NotZero(t, head)
		return head
	}

	transitionPaths, err := fs.Glob(os.DirFS("../../../../migrations"), "*_*.go")
	require.NoError(t, err)
	migrationPaths, err := fs.Glob(os.DirFS("../../../../migrations"), "*_*.up.sql")
	require.NoError(t, err)

	latestTransition := max(transforms.Map(transitionPaths, versionFromFile))
	latestMigration := max(transforms.Map(migrationPaths, versionFromFile))

	return latestTransition, latestTransition > latestMigration
}

func TestLatestTransition(t *testing.T) {
	latest, ok := latestCloudTransition(t)
	if !ok {
		t.Skip()
	}

	db := dbtest.RequireConnection(t)

	upgradeEnv := upgrades.NewEnv("../../../migrations", gormext.GetDB(db), MigrationsTable)

	transitions, err := migrations.Transitions.Build(upgradeEnv, &upgrades.Opts{})
	require.NoError(t, err)

	require.NoError(t, transitions[latest](context.Background()))
}
