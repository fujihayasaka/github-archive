package mysqldb

import (
	"context"
	"database/sql"
	"os"
	"testing"
	"time"

	"github.com/github/launch/observability/statter"

	errs "github.com/pkg/errors"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
)

func TestWithTransaction(t *testing.T) {
	conn, err := NewDB(statter.NullStatter(), os.Getenv("LAUNCH_DEPLOYER_TEST_DATABASE_URL"))
	require.NoError(t, err)

	_, err = conn.Exec("DROP TABLE IF EXISTS transaction_test")
	require.NoError(t, err)
	_, err = conn.Exec("CREATE TABLE transaction_test (id int, v varchar(255))")
	require.NoError(t, err)
	_, err = conn.Exec("INSERT INTO transaction_test (id,v) VALUES (1, 'a'), (2, 'b')")
	require.NoError(t, err)

	ctx := context.Background()
	operation := "operation"
	stat := &statter.MockStatter{}

	t.Run("returns commit failures", func(t *testing.T) {
		// cause the transaction to rollback before the sleep returns
		qctx, cancel := context.WithTimeout(ctx, time.Second/8)
		defer cancel()

		expected_tags := statter.Tags{
			"operation": operation,
			"error":     "true",
		}
		stat.On("Timing", mock.Anything, "act_transaction.time", expected_tags, mock.Anything).Once()

		err = WithTransaction(qctx, conn, stat, operation, func(tx *sql.Tx) error {
			_, err := tx.Exec("SELECT sleep(5)")
			require.NoError(t, err)
			return nil
		})

		assert.EqualError(t, err, "could not commit: sql: transaction has already been committed or rolled back")
	})

	t.Run("rolls back the transaction on error", func(t *testing.T) {
		expected_tags := statter.Tags{
			"operation": operation,
			"error":     "true",
		}
		stat.On("Timing", mock.Anything, "act_transaction.time", expected_tags, mock.Anything).Once()

		err = WithTransaction(ctx, conn, stat, operation, func(tx *sql.Tx) error {
			_, err := tx.Exec("UPDATE transaction_test SET v = 'updated' WHERE id = 1")
			require.NoError(t, err)
			return errs.New("test error")
		})

		require.EqualError(t, err, "test error")
		row := conn.QueryRow("SELECT v FROM transaction_test WHERE id = 1")
		var value string
		err := row.Scan(&value)
		require.NoError(t, err)
		require.Equal(t, "a", value)
	})

	t.Run("without errors, wrapped statements run as usual", func(t *testing.T) {
		expected_tags := statter.Tags{
			"operation": operation,
		}
		stat.On("Timing", mock.Anything, "act_transaction.time", expected_tags, mock.Anything).Once()

		err = WithTransaction(ctx, conn, stat, operation, func(tx *sql.Tx) error {
			_, err := tx.Exec("UPDATE transaction_test SET v = 'updated' WHERE id = 1")
			require.NoError(t, err)
			return nil
		})

		require.NoError(t, err)
		row := conn.QueryRow("SELECT v FROM transaction_test WHERE id = 1")
		var value string
		err := row.Scan(&value)
		require.NoError(t, err)
		require.Equal(t, "updated", value)
	})

	t.Run("records timing when there is a panic", func(t *testing.T) {
		expected_tags := statter.Tags{
			"operation": operation,
			"error":     "true",
		}

		defer func() {
			if r := recover(); r == nil {
				require.Fail(t, "expected panic")
			} else {
				stat.On("Timing", mock.Anything, "act_transaction.time", expected_tags, mock.Anything).Once()
			}
		}()

		err = WithTransaction(ctx, conn, stat, operation, func(tx *sql.Tx) error {
			panic("panic")
		})
	})
}
