package mysql

import (
	"testing"

	"github.com/DATA-DOG/go-sqlmock"
	"github.com/github/authnd/internal/common/db"
	"github.com/jmoiron/sqlx"
)

func WithMockExecutor(t *testing.T, fn func(ex TransactionExecutor, sqlMock sqlmock.Sqlmock)) {
	db.WithMockDB(t, func(mockDB *sqlx.DB, sqlMock sqlmock.Sqlmock) {
		ex := NewDefaultTransactionExecutor("mock", mockDB)
		fn(ex, sqlMock)
	})
}
