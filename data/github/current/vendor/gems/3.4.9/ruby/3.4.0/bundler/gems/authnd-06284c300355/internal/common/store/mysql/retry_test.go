package mysql

import (
	"context"
	"testing"

	"github.com/DATA-DOG/go-sqlmock"
	"github.com/github/authnd/internal/common/db"
	"github.com/go-sql-driver/mysql"
	"github.com/jmoiron/sqlx"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

type dummyModel struct {
	ID   int64  `db:"id"`
	Name string `db:"name"`
}

func TestRetries(t *testing.T) {
	db.WithMockDB(t, func(mockDB *sqlx.DB, sqlMock sqlmock.Sqlmock) {
		defer mockDB.Close()
		ctx := context.Background()

		rows := sqlmock.NewRows([]string{"id", "name"})
		rows.AddRow(1, "bob")
		rows.AddRow(2, "alice")
		for ix := 1; ix <= maxRetries; ix++ {
			sqlMock.ExpectQuery("SELECT `id`, `name` FROM fake_table LIMIT 1337").WillReturnError(mysql.ErrInvalidConn)
		}
		sqlMock.ExpectQuery("SELECT `id`, `name` FROM fake_table LIMIT 1337").WillReturnRows(rows)

		var models []dummyModel
		r := &retryableExecutor{ex: baseExecutor{"mock", mockDB}}

		err := r.SelectContext(ctx, &models, "SELECT `id`, `name` FROM fake_table LIMIT 1337")
		require.NoError(t, err)

		require.Len(t, models, 2)
		assert.Equal(t, int64(1), models[0].ID)
		assert.Equal(t, "bob", models[0].Name, "bob")
		assert.Equal(t, int64(2), models[1].ID)
		assert.Equal(t, "alice", models[1].Name)
	})
}

func TestRetries_RetriesExceeded(t *testing.T) {
	db.WithMockDB(t, func(mockDB *sqlx.DB, sqlMock sqlmock.Sqlmock) {
		defer mockDB.Close()
		ctx := context.Background()

		rows := sqlmock.NewRows([]string{"id", "name"})
		rows.AddRow(1, "bob")
		rows.AddRow(2, "alice")
		for ix := 1; ix <= maxRetries+1; ix++ {
			sqlMock.ExpectQuery("SELECT `id`, `name` FROM fake_table LIMIT 1337").WillReturnError(mysql.ErrInvalidConn)
		}

		var models []dummyModel
		r := &retryableExecutor{ex: baseExecutor{"mock", mockDB}}

		err := r.SelectContext(ctx, &models, "SELECT `id`, `name` FROM fake_table LIMIT 1337")
		require.ErrorIs(t, err, mysql.ErrInvalidConn)
	})
}

func TestRetries_NonRetryableError(t *testing.T) {
	db.WithMockDB(t, func(mockDB *sqlx.DB, sqlMock sqlmock.Sqlmock) {
		defer mockDB.Close()
		ctx := context.Background()

		sqlMock.ExpectQuery("SELECT `id`, `name` FROM fake_table LIMIT 1337").WillReturnError(mysql.ErrMalformPkt)

		var models []dummyModel
		r := &retryableExecutor{ex: baseExecutor{"mock", mockDB}}

		err := r.SelectContext(ctx, &models, "SELECT `id`, `name` FROM fake_table LIMIT 1337")
		require.ErrorIs(t, err, mysql.ErrMalformPkt)
	})
}
