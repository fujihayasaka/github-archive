package annotatesql

import (
	"context"
	"database/sql/driver"

	"github.com/github/go-queryannotations"
)

func newConn(conn driver.Conn, opts []queryannotations.Option) *wrappedConn {
	return &wrappedConn{
		Conn: conn,
		opts: opts,
	}
}

type wrappedConn struct {
	driver.Conn
	opts []queryannotations.Option
}

//

// annotate annotates the query
func (c *wrappedConn) annotate(ctx context.Context, query string) string {
	return queryannotations.Annotate(ctx, query, c.opts...)
}

//

var _ driver.ConnPrepareContext = (*wrappedConn)(nil)

func (c *wrappedConn) PrepareContext(ctx context.Context, query string) (driver.Stmt, error) {
	preparer, ok := c.Conn.(driver.ConnPrepareContext)
	if !ok {
		return nil, driver.ErrSkip
	}

	return preparer.PrepareContext(ctx, query)
}

//

var _ driver.ConnBeginTx = (*wrappedConn)(nil)

func (c *wrappedConn) BeginTx(ctx context.Context, opts driver.TxOptions) (driver.Tx, error) {
	beginTx, ok := c.Conn.(driver.ConnBeginTx)
	if !ok {
		return nil, driver.ErrSkip
	}

	return beginTx.BeginTx(ctx, opts)
}

//

//nolint:staticcheck
var _ driver.Queryer = (*wrappedConn)(nil)

func (c *wrappedConn) Query(query string, args []driver.Value) (driver.Rows, error) {
	//nolint:staticcheck
	queryer, ok := c.Conn.(driver.Queryer)
	if !ok {
		return nil, driver.ErrSkip
	}

	return queryer.Query(c.annotate(context.Background(), query), args)
}

//

var _ driver.QueryerContext = (*wrappedConn)(nil)

func (c *wrappedConn) QueryContext(ctx context.Context, query string, args []driver.NamedValue) (driver.Rows, error) {
	queryer, ok := c.Conn.(driver.QueryerContext)
	if !ok {
		return nil, driver.ErrSkip
	}

	return queryer.QueryContext(ctx, c.annotate(ctx, query), args)
}

//
//nolint:staticcheck
var _ driver.Execer = (*wrappedConn)(nil)

func (c *wrappedConn) Exec(query string, args []driver.Value) (driver.Result, error) {
	//nolint:staticcheck
	execer, ok := c.Conn.(driver.Execer)
	if !ok {
		return nil, driver.ErrSkip
	}

	return execer.Exec(c.annotate(context.Background(), query), args)
}

//

var _ driver.ExecerContext = (*wrappedConn)(nil)

func (c *wrappedConn) ExecContext(ctx context.Context, query string, args []driver.NamedValue) (driver.Result, error) {
	execerCtx, ok := c.Conn.(driver.ExecerContext)
	if !ok {
		return nil, driver.ErrSkip
	}

	return execerCtx.ExecContext(ctx, c.annotate(ctx, query), args)
}

//

var _ driver.Pinger = (*wrappedConn)(nil)

func (c *wrappedConn) Ping(ctx context.Context) error {
	pinger, ok := c.Conn.(driver.Pinger)
	if !ok {
		return driver.ErrSkip
	}

	return pinger.Ping(ctx)
}

//

var _ driver.NamedValueChecker = (*wrappedConn)(nil)

func (c *wrappedConn) CheckNamedValue(value *driver.NamedValue) error {
	checker, ok := c.Conn.(driver.NamedValueChecker)
	if !ok {
		return driver.ErrSkip
	}

	return checker.CheckNamedValue(value)
}

//

var _ driver.SessionResetter = (*wrappedConn)(nil)

func (c *wrappedConn) ResetSession(ctx context.Context) error {
	sessionResetter, ok := c.Conn.(driver.SessionResetter)
	if !ok {
		return driver.ErrSkip
	}

	return sessionResetter.ResetSession(ctx)
}
