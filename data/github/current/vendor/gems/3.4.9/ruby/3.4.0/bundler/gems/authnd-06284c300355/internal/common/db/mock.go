package db

import (
	"testing"

	"github.com/DATA-DOG/go-sqlmock"
	"github.com/jmoiron/sqlx"
	"github.com/stretchr/testify/require"
)

func WithMockDB(t *testing.T, fn func(db *sqlx.DB, sqlMock sqlmock.Sqlmock)) {
	mockDB, sqlMock, err := sqlmock.New()
	require.NoError(t, err)
	sqlxDB := sqlx.NewDb(mockDB, "sqlmock")

	fn(sqlxDB, sqlMock)

	mockDB.Close()

	if err := sqlMock.ExpectationsWereMet(); err != nil {
		t.Errorf("there were unfulfilled expectations: %s", err)
	}
}
