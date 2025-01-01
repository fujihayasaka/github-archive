package asql

import (
	"context"
	"database/sql"
	"os"
	"testing"

	"github.com/github/launch/mysqldb"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/statter"

	throttler "github.com/github/go-freno-client"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestBatchIterator(t *testing.T) {
	sql, min, max := createRows(t, 10)

	it := BatchIterator{
		Obs:         observability.NewNullObservability(),
		DB:          sql,
		DBThrottler: throttler.DefaultThrottler,
		BatchSize:   2,
		Start:       min,
		End:         max - 1,
	}

	ctx := context.Background()

	newValue := "foo"
	newName := "bar"

	var count int
	row := sql.QueryRow("SELECT COUNT(*) FROM asql_iterator_test WHERE value = ? AND id >= ? AND id <= ?", newValue, min, max)
	err := row.Scan(&count)
	require.NoError(t, err)
	assert.Equal(t, 0, count)

	query := `UPDATE asql_iterator_test SET value = ?, name = ? WHERE id >= {{.Min}} AND id <= {{.Max}}`
	res, err := it.Run(ctx, query, newValue, newName)
	require.NoError(t, err)
	assert.Equal(t, int64(9), res.RowsAffected)
	assert.Equal(t, int64(5), res.SuccessfulIterations)

	row = sql.QueryRow("SELECT COUNT(*) FROM asql_iterator_test WHERE value = ? AND id >= ? AND id <= ?", newValue, min, max)
	err = row.Scan(&count)
	require.NoError(t, err)
	assert.Equal(t, 9, count)
}

func TestBatchIterator_QueryWithExtraTemplateParam(t *testing.T) {
	sql, min, max := createRows(t, 1)

	it := BatchIterator{
		Obs:         observability.NewNullObservability(),
		DB:          sql,
		DBThrottler: throttler.DefaultThrottler,
		BatchSize:   2,
		Start:       min,
		End:         max - 1,
	}

	query := `UPDATE asql_iterator_test SET value = {{.Val}}`
	_, err := it.Run(context.Background(), query)
	assert.Error(t, err)
}

func TestBatchIterator_QueryWithoutMinMax(t *testing.T) {
	sql, min, max := createRows(t, 1)

	it := BatchIterator{
		Obs:         observability.NewNullObservability(),
		DB:          sql,
		DBThrottler: throttler.DefaultThrottler,
		BatchSize:   2,
		Start:       min,
		End:         max - 1,
	}

	query := `UPDATE asql_iterator_test SET value = ?`
	_, err := it.Run(context.Background(), query, "foo")
	assert.Error(t, err)
}

func TestBatchIterator_MinLessThanMax(t *testing.T) {
	it := BatchIterator{
		Obs:       observability.NewNullObservability(),
		BatchSize: 2,
		Start:     1,
		End:       0,
	}

	query := `UPDATE asql_iterator_test SET value = ?, name = ? WHERE id >= {{.Min}} AND id <= {{.Max}}`
	_, err := it.Run(context.Background(), query, "foo")
	assert.Error(t, err)
}

func TestBatchIterator_NothingToIterate(t *testing.T) {
	it := BatchIterator{
		Obs:         observability.NewNullObservability(),
		DBThrottler: throttler.DefaultThrottler,
		DB: execerfunc(func(ctx context.Context, sql string, params ...any) (sql.Result, error) {
			return nilResult{}, nil
		}),
		BatchSize: 100,
		Start:     1366751143,
		End:       1366751242,
	}

	ctx := context.Background()
	res, err := it.Run(ctx, "{{.Min}} {{.Max}}")
	require.NoError(t, err)
	require.Equal(t, result{RowsAffected: -1, SuccessfulIterations: 1}, res)
}

type execerfunc func(ctx context.Context, sql string, params ...any) (sql.Result, error)

func (fn execerfunc) ExecContext(ctx context.Context, sql string, params ...any) (sql.Result, error) {
	return fn(ctx, sql, params...)
}

type nilResult struct {
}

func (dr nilResult) LastInsertId() (int64, error) {
	return -1, nil
}

func (dr nilResult) RowsAffected() (int64, error) {
	return -1, nil
}

func createRows(t *testing.T, numRows int) (*sql.Tx, int64, int64) {
	db, err := mysqldb.NewDB(statter.NullStatter(), os.Getenv("LAUNCH_DEPLOYER_TEST_DATABASE_URL"))
	require.NoError(t, err)

	_, err = db.Exec(`
		DROP TABLE IF EXISTS asql_iterator_test
	`)
	require.NoError(t, err)
	_, err = db.Exec(`
		CREATE TABLE asql_iterator_test (
		    id int PRIMARY KEY AUTO_INCREMENT,
				name varchar(30),
		    value varchar(30)
		)
	`)
	require.NoError(t, err)

	ctx := context.Background()
	tx, err := db.BeginTx(ctx, nil)
	require.NoError(t, err)

	_, err = tx.ExecContext(context.Background(), "DELETE FROM asql_iterator_test;")
	require.NoError(t, err)

	for i := 0; i < 10; i++ {
		sql := `INSERT INTO asql_iterator_test (value) VALUES (?)`
		_, err := tx.ExecContext(ctx, sql, i)
		require.NoError(t, err)
	}
	t.Cleanup(func() {
		tx.Rollback()
	})

	var min, max int64
	row := tx.QueryRow("SELECT min(id), max(id) FROM asql_iterator_test")
	err = row.Scan(&min, &max)
	require.NoError(t, err)

	return tx, min, max
}
