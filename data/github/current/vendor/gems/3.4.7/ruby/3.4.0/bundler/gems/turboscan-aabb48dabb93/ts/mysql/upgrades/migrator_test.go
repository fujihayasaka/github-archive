// These tests exercise both migration and transition functionality.
//
// The tests in this file are tagged (and therefore not run by default) because
// they rely on executing "skeema" as a subprocess. They can be run reliably
// using `script/dev-run` inside Docker and are also run during CI.
//
// An example command for running a subset of these tests using `script/dev-run` is:
// go test -p 1 -race -tags migrator -run TestTransition ./ts/mysql/upgrades
package upgrades_test

import (
	"context"
	"database/sql"
	"os/exec"
	"testing"
	"time"

	"github.com/github/turboscan/ts/mysql/upgrades"
	"github.com/go-sql-driver/mysql"

	"github.com/stretchr/testify/require"
)

const migrationsTable = "migrations"

func dbConfig() *mysql.Config {
	cfg := mysql.NewConfig()
	cfg.Net = "tcp"
	cfg.User = "root"
	cfg.Addr = "localhost:13806"
	cfg.ParseTime = true
	cfg.InterpolateParams = true // forces statements to be prepared client-side see https://github.com/github/database-infrastructure/issues/2260#issuecomment-538617856
	cfg.Collation = "utf8mb4_general_ci"
	cfg.MultiStatements = false
	cfg.CheckConnLiveness = true
	cfg.Params = map[string]string{
		"charset": "utf8mb4",
	}
	return cfg
}

func enterpriseTestDB(t *testing.T) *sql.DB {
	t.Helper()

	cfg := dbConfig()
	cfg.DBName = "enterprise_test"

	testdb, err := sql.Open("mysql", cfg.FormatDSN())
	require.NoError(t, err)
	require.NoError(t, testdb.Ping())
	t.Cleanup(func() {
		require.NoError(t, testdb.Close())
	})
	return testdb
}

func cleanEnterpriseTestDB(t *testing.T) *sql.DB {
	t.Helper()

	cfg := dbConfig()

	testdb, err := sql.Open("mysql", cfg.FormatDSN())

	defer func() {
		err = testdb.Close()
		require.NoError(t, err)
	}()

	_, err = testdb.Exec("drop database if exists enterprise_test")
	require.NoError(t, err)

	_, err = testdb.Exec("create database enterprise_test CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci")
	require.NoError(t, err)

	return enterpriseTestDB(t)
}

func skeemaDiff(t *testing.T) (string, error) {
	t.Helper()

	t.Log("skeema", "diff", "--allow-unsafe", "--ignore-table", migrationsTable, "enterprisetest")
	cmd := exec.Command("skeema", "diff", "--allow-unsafe", "--ignore-table", migrationsTable, "enterprisetest")
	cmd.Dir = "testdata/schemas"
	output, err := cmd.CombinedOutput()
	t.Log(string(output))
	t.Log(err)
	return string(output), err
}

func runMigrations(t *testing.T, migrationsDir string, migrationOpts *upgrades.Opts, sqlTransitions func(env *upgrades.Env, opts *upgrades.Opts) (map[uint]func(ctx context.Context) error, error), checkFun func(*testing.T, *sql.DB)) error {
	t.Helper()

	db := cleanEnterpriseTestDB(t)

	if migrationOpts == nil {
		migrationOpts = &upgrades.Opts{}
	}

	upgradeEnv := upgrades.NewEnv(migrationsDir, db, migrationsTable)

	transitions, err := sqlTransitions(upgradeEnv, migrationOpts)
	require.NoError(t, err)

	if err = upgradeEnv.RunMigrations(context.Background(), transitions); err != nil {
		return err
	}

	if checkFun != nil {
		// RunMigrations closes its db, so we have to open a new connection
		checkFun(t, enterpriseTestDB(t))
	}
	return nil
}

func runMigrationsOnly(t *testing.T, migrationsDir string, migrationOpts *upgrades.Opts, sqlTransitions func(env *upgrades.Env, opts *upgrades.Opts) (map[uint]func(ctx context.Context) error, error)) error {
	t.Helper()

	return runMigrations(t, migrationsDir, migrationOpts, sqlTransitions, nil)
}

func runMigrationsAndDiffSchema(t *testing.T, migrationsDir string, sqlTransitions func(env *upgrades.Env, opts *upgrades.Opts) (map[uint]func(ctx context.Context) error, error), checkFun func(*testing.T, *sql.DB)) (string, error) {
	t.Helper()

	err := runMigrations(t, migrationsDir, nil, sqlTransitions, checkFun)
	require.NoError(t, err)

	return skeemaDiff(t)
}

func readStrings(t *testing.T, db *sql.DB, sql string, args ...interface{}) []string {
	t.Helper()

	rows, err := db.Query(sql, args...)
	require.NoError(t, err)
	defer rows.Close()

	var elems []string
	for rows.Next() {
		var elem string
		err := rows.Scan(&elem)
		require.NoError(t, err)

		elems = append(elems, elem)
	}
	require.NoError(t, rows.Err())

	return elems
}

func TestSyntheticMigrationsGood(t *testing.T) {
	tr := upgrades.Transitions()
	output, err := runMigrationsAndDiffSchema(t, "testdata/migrations-good", tr.Build, nil)
	require.NoError(t, err, output)
}

func TestSyntheticMigrationsBad(t *testing.T) {
	tr := upgrades.Transitions()
	output, err := runMigrationsAndDiffSchema(t, "testdata/migrations-bad", tr.Build, nil)
	require.Error(t, err, output)
}

func TestTransitionGood(t *testing.T) {
	v := upgrades.Transitions()
	v.Version(20200618175824).Step(0).Simple(
		"INSERT IGNORE INTO mytable (id) VALUES(1),(2),(3)",
		"INSERT IGNORE INTO mytable (id) VALUES(4),(5),(6)",
		"UPDATE mytable SET id = id + 10 WHERE id < 10 LIMIT 4",
	)
	v.Version(20200618175826).Step(1).Simple(`UPDATE mytable SET stringcol = CAST(id AS CHAR) WHERE stringcol = "" LIMIT ?`)

	output, err := runMigrationsAndDiffSchema(t, "testdata/migrations-good", v.Build, func(t *testing.T, db *sql.DB) {
		t.Helper()
		ss := readStrings(t, db, "SELECT stringcol from mytable")
		require.Equal(t, []string{"11", "12", "13", "14", "15", "16"}, ss)
	})
	require.NoError(t, err, output)

}

func TestBatchedTransition(t *testing.T) {
	v := upgrades.Transitions()
	v.Version(20200618175824).Step(0).Simple(
		"INSERT IGNORE INTO mytable (id) VALUES(1),(2),(3)",
		"INSERT IGNORE INTO mytable (id) VALUES(4),(5),(6)",
		"UPDATE mytable SET id = id + 10 WHERE id < 10 LIMIT 4",
	)
	v.Version(20200618175826).Batched("mytable", "UPDATE mytable SET stringcol = CAST(id AS CHAR) WHERE id BETWEEN ? AND ?")

	output, err := runMigrationsAndDiffSchema(t, "testdata/migrations-good", v.Build, func(t *testing.T, db *sql.DB) {
		t.Helper()
		ss := readStrings(t, db, "SELECT stringcol from mytable")
		require.Equal(t, []string{"11", "12", "13", "14", "15", "16"}, ss)
	})
	require.NoError(t, err, output)
}

func TestDynamicRetry(t *testing.T) {
	var called int

	expected := []struct{ start, end uint64 }{
		// try twice to see if the error is transient
		{100, 149},
		{100, 149},
		// halve the step
		{100, 124},
		// halve the step again
		// the error stops happening
		{100, 112},
		{113, 125},
		{126, 138},
		{139, 149},
		// nextVersion partition, step back to default
		{150, 199},
		{200, 200},
	}

	v := upgrades.Transitions()
	v.Version(20200618175826).Function("mytable", func(ctx context.Context, db upgrades.DB, start, end uint64) error {
		require.Equal(t, expected[called].start, start)
		require.Equal(t, expected[called].end, end)
		called += 1
		if called < 4 {
			return &mysql.MySQLError{Number: 1317, Message: "statement timed out"}
		}
		return nil
	})

	err := runMigrationsOnly(t, "testdata/migrations-good", &upgrades.Opts{MinID: 100, MaxID: 200, Step: 50}, v.Build)
	require.NoError(t, err)
	require.Equal(t, len(expected), called)
}

// TestDynamicRetryMakesProgress ensures that the retry makes progress even when the step size reaches 1.
func TestDynamicRetryMakesProgress(t *testing.T) {
	called := 0

	v := upgrades.Transitions()
	v.Version(20200618175826).Function("mytable", func(ctx context.Context, db upgrades.DB, start, end uint64) error {
		called += 1
		if called < 4 {
			return &mysql.MySQLError{Number: 1317, Message: "statement timed out"}
		}
		return nil
	})

	err := runMigrationsOnly(t, "testdata/migrations-good", &upgrades.Opts{MinID: 100, MaxID: 200, Step: 2}, v.Build)
	require.NoError(t, err)
	require.Equal(t, 55, called)
}

func TestTransitionTimedOut(t *testing.T) {
	v := upgrades.Transitions()
	v.Version(20200618175824).Simple("INSERT IGNORE INTO mytable (id) VALUES(1),(2),(3)")
	v.Version(20200618175826).Batched("mytable", "SELECT SLEEP(10) FROM mytable WHERE id BETWEEN ? AND ?")

	now := time.Now()
	err := runMigrationsOnly(t, "testdata/migrations-good", &upgrades.Opts{Timeout: 1 * time.Millisecond}, v.Build)
	require.Less(t, time.Since(now), 10*time.Second)
	require.Error(t, err)
}

func TestTransitionHeartbeat(t *testing.T) {
	v := upgrades.Transitions()
	v.Version(20200618175824).Step(0).Simple("INSERT IGNORE INTO mytable (id) VALUES(1),(2),(3)")
	v.Version(20200618175826).Step(1).Batched("mytable", "SELECT SLEEP(10/1000) FROM mytable WHERE id BETWEEN ? AND ?")

	err := runMigrationsOnly(t, "testdata/migrations-good", &upgrades.Opts{Timeout: 25 * time.Millisecond}, v.Build)
	require.NoError(t, err)
}

func TestTransitionCompletedBeforeTimeout(t *testing.T) {
	v := upgrades.Transitions()
	v.Version(20200618175824).Step(0).Simple("INSERT IGNORE INTO mytable (id) VALUES(1)")
	v.Version(20200618175826).Batched("mytable", "SELECT id FROM mytable WHERE id BETWEEN ? AND ?")

	err := runMigrationsOnly(t, "testdata/migrations-good", &upgrades.Opts{Timeout: 10 * time.Second}, v.Build)
	require.NoError(t, err)
}

func TestTransitionModifiesSchema(t *testing.T) {
	v := upgrades.Transitions()
	v.Version(20200618175824).Step(0).Simple("CREATE TABLE `badtable` (`stringcol` varchar(200) NOT NULL) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;")

	output, err := runMigrationsAndDiffSchema(t, "testdata/migrations-good", v.Build, nil)
	require.Error(t, err, output)
}

func TestTransitionBad(t *testing.T) {
	v := upgrades.Transitions()
	v.Version(20200618175825).Simple(`UPDATE mytable SET stringcol = "hello"`)

	err := runMigrationsOnly(t, "testdata/migrations-good", nil, v.Build)

	require.Error(t, err)
	// The column `stringcol` is created in a migration that has not run yet (20200618175826)
	require.Contains(t, err.Error(), "Unknown column 'stringcol'")
}
