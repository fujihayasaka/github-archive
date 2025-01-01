package mysql

import (
	"context"
	"testing"

	"github.com/DATA-DOG/go-sqlmock"
	"github.com/github/authnd/internal/common"
	"github.com/golang/mock/gomock"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

type testThrottler struct {
	CanWriteFn func(ctx context.Context) (bool, error)
}

func (t *testThrottler) CanWrite(ctx context.Context) (bool, error) {
	return t.CanWriteFn(ctx)
}

func TestThrottling_ReadsAreNotThrottled(t *testing.T) {
	WithMockExecutor(t, func(mockExecutor TransactionExecutor, sqlMock sqlmock.Sqlmock) {
		// always throttle writes
		ct := &testThrottler{
			CanWriteFn: func(ctx context.Context) (bool, error) {
				return false, nil
			},
		}

		ctrl := gomock.NewController(t)
		defer ctrl.Finish()

		r := &throttlingExecutor{ex: mockExecutor, throttler: ct}

		t.Run("Select", func(t *testing.T) {
			rows := sqlmock.NewRows([]string{"id", "name"})
			rows.AddRow(1, "bob")
			rows.AddRow(2, "alice")
			sqlMock.ExpectQuery("SELECT `id`, `name` FROM fake_table LIMIT 1337").WillReturnRows(rows)

			var models []dummyModel
			err := r.SelectContext(context.Background(), &models, "SELECT `id`, `name` FROM fake_table LIMIT 1337")
			require.NoError(t, err)

			require.Len(t, models, 2)
			assert.Equal(t, int64(1), models[0].ID)
			assert.Equal(t, "bob", models[0].Name)
			assert.Equal(t, int64(2), models[1].ID)
			assert.Equal(t, "alice", models[1].Name)
		})

		t.Run("Get", func(t *testing.T) {
			rows := sqlmock.NewRows([]string{"id", "name"})
			rows.AddRow(1, "bob")
			sqlMock.ExpectQuery("SELECT `id`, `name` FROM fake_table WHERE id = 1").WillReturnRows(rows)

			var model dummyModel
			err := r.GetContext(context.Background(), &model, "SELECT `id`, `name` FROM fake_table WHERE id = 1")
			require.NoError(t, err)

			assert.Equal(t, int64(1), model.ID)
			assert.Equal(t, "bob", model.Name)
		})
	})
}

func TestThrottling_WritesAreThrottled(t *testing.T) {
	WithMockExecutor(t, func(mockExecutor TransactionExecutor, sqlMock sqlmock.Sqlmock) {

		ctrl := gomock.NewController(t)
		defer ctrl.Finish()

		r := &throttlingExecutor{ex: mockExecutor,
			throttler: &testThrottler{
				CanWriteFn: func(ctx context.Context) (bool, error) {
					// throttle writes
					return false, nil
				},
			},
		}

		t.Run("Throttled", func(t *testing.T) {
			_, err := r.ExecContext(context.Background(), "INSERT INTO fake_table (1,alice)")
			require.Error(t, err)
			assert.ErrorIs(t, err, common.WriteThrottledError)
		})

		r.throttler = &testThrottler{
			CanWriteFn: func(ctx context.Context) (bool, error) {
				// don't throttle writes
				return true, nil
			},
		}

		t.Run("Unthrottled", func(t *testing.T) {
			sqlMock.ExpectExec("INSERT INTO fake_table").WillReturnResult(sqlmock.NewResult(1337, 1))

			result, err := r.ExecContext(context.Background(), "INSERT INTO fake_table")
			assert.NoError(t, err)

			id, err := result.LastInsertId()
			require.NoError(t, err)
			assert.Equal(t, int64(1337), id)

			affected, err := result.RowsAffected()
			require.NoError(t, err)
			assert.Equal(t, int64(1), affected)
		})
	})
}

func TestThrottling_TransactionsAreProtected(t *testing.T) {
	WithMockExecutor(t, func(mockExecutor TransactionExecutor, sqlMock sqlmock.Sqlmock) {
		ctrl := gomock.NewController(t)
		defer ctrl.Finish()

		t.Run("Throttled", func(t *testing.T) {
			r := &throttlingExecutor{ex: mockExecutor,
				throttler: &testThrottler{
					CanWriteFn: func(ctx context.Context) (bool, error) {
						// throttle writes
						return false, nil
					},
				},
			}
			ex := NewTransactionExecutor(r)

			var transactionStarted bool
			err := ex.WithTransaction(context.Background(), func(_ Executor) error {
				transactionStarted = true
				return nil
			})

			require.ErrorIs(t, err, common.WriteThrottledError)
			assert.False(t, transactionStarted)
		})

		t.Run("No throttled", func(t *testing.T) {
			r := &throttlingExecutor{ex: mockExecutor,
				throttler: &testThrottler{
					CanWriteFn: func(ctx context.Context) (bool, error) {
						// no throttling
						return true, nil
					},
				},
			}
			ex := NewTransactionExecutor(r)

			sqlMock.ExpectBegin()
			sqlMock.ExpectCommit()

			var transactionStarted bool
			err := ex.WithTransaction(context.Background(), func(_ Executor) error {
				transactionStarted = true
				return nil
			})

			assert.NoError(t, err)
			assert.True(t, transactionStarted)
		})
	})
}
