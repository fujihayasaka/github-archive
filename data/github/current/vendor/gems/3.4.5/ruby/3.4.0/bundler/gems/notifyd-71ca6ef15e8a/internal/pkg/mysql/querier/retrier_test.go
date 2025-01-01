package querier

import (
	"context"
	"database/sql"
	"database/sql/driver"
	"errors"
	"testing"

	"github.com/Masterminds/squirrel"
	"github.com/benbjohnson/clock"
	gomysql "github.com/go-sql-driver/mysql"
	"github.com/jmoiron/sqlx"
	"github.com/stretchr/testify/require"

	"github.com/github/notifyd/internal/pkg/o11y/logs"
)

type retrierTest struct {
	name    string
	err     error
	retried bool
}

var retrierTests = []retrierTest{
	// no retried
	{name: "no error", err: nil, retried: false},
	{name: "non retriable error", err: errors.New("oops"), retried: false},

	// retried
	{name: "invalid connection", err: gomysql.ErrInvalidConn, retried: true},
	{name: "bad connecection", err: driver.ErrBadConn, retried: true},
}

func Test_retrier_Delete(t *testing.T) {
	ctx := context.Background()

	for _, test := range retrierTests {
		t.Run(test.name, func(t *testing.T) {
			fake := &fake{err: test.err}
			retrier := newMock(t, fake)

			var dst interface{}
			err := retrier.Select(ctx, store{}, &dst, squirrel.Delete("*").From("table"))
			assertRetries(t, fake, test, err)
		})
	}
}

func Test_retrier_Insert(t *testing.T) {
	ctx := context.Background()

	for _, test := range retrierTests {
		t.Run(test.name, func(t *testing.T) {
			fake := &fake{err: test.err}
			retrier := newMock(t, fake)

			_, err := retrier.Insert(ctx, store{}, squirrel.Insert("table").Columns("name").Values("fran"))
			assertRetries(t, fake, test, err)
		})
	}
}

func Test_retrier_Select(t *testing.T) {
	ctx := context.Background()

	for _, test := range retrierTests {
		t.Run(test.name, func(t *testing.T) {
			fake := &fake{err: test.err}
			retrier := newMock(t, fake)

			var dst interface{}
			err := retrier.Select(ctx, store{}, &dst, squirrel.Select("*").From("table"))
			assertRetries(t, fake, test, err)
		})
	}
}

func newMock(t *testing.T, f *fake) Querier {
	t.Helper()

	retrier := NewRetrier(f, clock.NewMock(), logs.NullTelem)

	return retrier
}

func assertRetries(t *testing.T, f *fake, test retrierTest, err error) {
	r := require.New(t)
	// On retriable errors
	if test.retried {
		r.NoError(err)
		r.Equal(2, f.called)
		return
	}

	// On non retriable errors
	if !test.retried && test.err != nil {
		r.Error(err)
		r.Equal(1, f.called)
		return
	}

	// On non-erroring calls
	r.NoError(err)
	r.Equal(1, f.called)
}

// fake is a querier that always returns an error the first time it is called and success the next
// times. It also tracks how many times it has been called.
type fake struct {
	called int
	err    error
}

func (r *fake) Delete(ctx context.Context, store sqlx.ExecerContext, query squirrel.Sqlizer) error {
	r.called++
	if r.called == 1 {
		return r.err
	}
	return nil
}

func (r *fake) Select(ctx context.Context, store sqlx.QueryerContext, dst interface{}, query squirrel.Sqlizer) error {
	r.called++
	if r.called == 1 {
		return r.err
	}
	return nil
}

func (r *fake) Insert(ctx context.Context, store sqlx.ExecerContext, query squirrel.Sqlizer) (Result, error) {
	r.called++
	if r.called == 1 {
		return Result{}, r.err
	}

	return Result{}, nil
}

func (r *fake) AutoIncrementStep(ctx context.Context, tx *sqlx.Tx) (int64, error) {
	return 1, nil
}

// store is a mock of a database connection. Does nothing, returns nothing and it is only here so
// that it can be passed around in tests.
type store struct{}

func (s store) ExecContext(ctx context.Context, query string, args ...interface{}) (sql.Result, error) {
	return Result{}, nil
}

func (s store) QueryContext(ctx context.Context, query string, args ...interface{}) (*sql.Rows, error) {
	return &sql.Rows{}, nil
}

func (s store) QueryxContext(ctx context.Context, query string, args ...interface{}) (*sqlx.Rows, error) {
	return &sqlx.Rows{}, nil
}

func (s store) QueryRowxContext(ctx context.Context, query string, args ...interface{}) *sqlx.Row {
	return &sqlx.Row{}
}
