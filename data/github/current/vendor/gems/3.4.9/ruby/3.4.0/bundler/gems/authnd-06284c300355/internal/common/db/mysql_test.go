package db

import (
	"context"
	"testing"

	"github.com/pkg/errors"

	"github.com/DATA-DOG/go-sqlmock"
	"github.com/jmoiron/sqlx"
	"github.com/stretchr/testify/require"
)

func TestWithTransactionCommit(t *testing.T) {
	WithMockDB(t, func(db *sqlx.DB, mock sqlmock.Sqlmock) {
		query := "DELETE FROM `some_table`"
		mock.ExpectBegin()
		mock.ExpectExec(query).WillReturnResult(sqlmock.NewResult(1, 1))
		mock.ExpectCommit()

		err := WithTransaction(context.Background(), db, func(tx *sqlx.Tx) error {
			_, err := tx.Exec(query)
			return err
		})
		require.NoError(t, err)
	})
}

func TestWithTransactionError(t *testing.T) {
	WithMockDB(t, func(db *sqlx.DB, mock sqlmock.Sqlmock) {
		query := "DELETE FROM `some_table`"
		mock.ExpectBegin()
		mock.ExpectExec(query).WillReturnResult(sqlmock.NewResult(1, 1))
		mock.ExpectRollback()

		err := WithTransaction(context.Background(), db, func(tx *sqlx.Tx) error {
			_, err := tx.Exec(query)
			require.NoError(t, err)
			return errors.New("oh no!")
		})

		require.Error(t, err)
	})
}

func TestWithTransactionCommitError(t *testing.T) {
	WithMockDB(t, func(db *sqlx.DB, mock sqlmock.Sqlmock) {
		query := "DELETE FROM `some_table`"
		mock.ExpectBegin()
		mock.ExpectExec(query).WillReturnResult(sqlmock.NewResult(1, 1))
		mock.ExpectCommit().WillReturnError(errors.New("oh no!"))

		err := WithTransaction(context.Background(), db, func(tx *sqlx.Tx) error {
			_, err := tx.Exec(query)
			return err
		})
		require.Error(t, err, "")
	})
}

func TestWithTransactionPanic(t *testing.T) {
	WithMockDB(t, func(db *sqlx.DB, mock sqlmock.Sqlmock) {
		query := "DELETE FROM `some_table`"
		mock.ExpectBegin()
		mock.ExpectExec(query).WillReturnResult(sqlmock.NewResult(1, 1))
		mock.ExpectRollback()

		defer func() {
			if p := recover(); p != nil {
				if err := mock.ExpectationsWereMet(); err != nil {
					t.Errorf("there were unfulfilled expectations: %s", err)
				}
			} else {
				t.Errorf("expected panic")
			}
		}()

		_ = WithTransaction(context.Background(), db, func(tx *sqlx.Tx) error {
			_, err := tx.Exec(query)
			require.NoError(t, err)
			panic("oh no!")
		})
	})
}

func TestIDRangeWhereClause(t *testing.T) {
	expectedResult := "id >= 1 AND id <= 5"
	result := IDRangeWhereClause(1, 5)
	require.Equal(t, expectedResult, result)
}

func TestIDInWhereClause(t *testing.T) {
	expectedResult := "id in (1, 2, 3)"
	result := IDInWhereClause([]int64{1, 2, 3})
	require.Equal(t, expectedResult, result)
}

func TestIDInWhereClauseOneItem(t *testing.T) {
	expectedResult := "id in (1)"
	result := IDInWhereClause([]int64{1})
	require.Equal(t, expectedResult, result)
}

func TestIDInWhereClauseEmptySlice(t *testing.T) {
	expectedResult := "id in ()"
	result := IDInWhereClause([]int64{})
	require.Equal(t, expectedResult, result)
}
