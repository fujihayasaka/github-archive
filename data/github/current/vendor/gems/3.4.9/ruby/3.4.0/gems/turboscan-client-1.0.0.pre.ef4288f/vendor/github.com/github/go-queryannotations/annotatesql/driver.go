package annotatesql

import (
	"context"
	"database/sql"

	"database/sql/driver"

	"github.com/github/go-queryannotations"
)

// Open opens a sql connection wrapped with query annotations.
func Open(driverName, dsn string, opts ...queryannotations.Option) (*sql.DB, error) {
	db, err := sql.Open(driverName, dsn)
	if err != nil {
		return nil, err
	}

	return AdaptDB(db, dsn, opts...)
}

// OpenDB opens a DB using the given connector
func OpenDB(c driver.Connector, opts ...queryannotations.Option) *sql.DB {
	d := c.Driver()

	qd := &queryCommentDriver{
		wd:   d,
		opts: opts,
	}

	connector := newConnector(c, qd)
	return sql.OpenDB(connector)
}

// AdaptConn adapts an existing driver.Connector to use query annotations.
func AdaptConn(conn driver.Connector, opts ...queryannotations.Option) driver.Connector {
	d := conn.Driver()

	qd := &queryCommentDriver{
		wd:   d,
		opts: opts,
	}

	return newConnector(conn, qd)
}

// AdaptDB adapts an existing sql.DB to use query annotations.
//
// It does so by closing the existing DB, wrapping the driver, and re-opening the connection.
func AdaptDB(db *sql.DB, dsn string, opts ...queryannotations.Option) (*sql.DB, error) {
	d := db.Driver()

	if err := db.Close(); err != nil {
		return nil, err
	}

	qd := &queryCommentDriver{
		wd:   d,
		opts: opts,
	}

	if _, ok := d.(driver.DriverContext); ok {
		connector, err := qd.OpenConnector(dsn)
		if err != nil {
			return nil, err
		}

		return sql.OpenDB(connector), nil
	}

	return sql.OpenDB(&dsnConnector{
		d:   qd,
		dsn: dsn,
	}), nil
}

//

type queryCommentDriver struct {
	wd   driver.Driver
	opts []queryannotations.Option
}

func (d *queryCommentDriver) Open(name string) (driver.Conn, error) {
	conn, err := d.wd.Open(name)
	if err != nil {
		return nil, err
	}

	return newConn(conn, d.opts), nil
}

func (d *queryCommentDriver) OpenConnector(name string) (driver.Connector, error) {
	driverContext, ok := d.wd.(driver.DriverContext)
	if !ok {
		return newDSNConnector(name, d), nil
	}

	connector, err := driverContext.OpenConnector(name)
	if err != nil {
		return nil, err
	}

	return newConnector(connector, d), nil
}

func newConnector(c driver.Connector, d *queryCommentDriver) *connector {
	return &connector{
		wc: c,
		d:  d,
	}
}

type connector struct {
	wc driver.Connector
	d  *queryCommentDriver
}

func (c *connector) Connect(ctx context.Context) (driver.Conn, error) {
	conn, err := c.wc.Connect(ctx)
	if err != nil {
		return nil, err
	}

	return newConn(conn, c.d.opts), nil
}

func (c *connector) Driver() driver.Driver {
	return c.d
}

func newDSNConnector(dsn string, d *queryCommentDriver) *dsnConnector {
	return &dsnConnector{
		dsn: dsn,
		d:   d,
	}
}

type dsnConnector struct {
	dsn string
	d   *queryCommentDriver
}

func (c *dsnConnector) Connect(context.Context) (driver.Conn, error) {
	return c.d.Open(c.dsn)
}

func (c *dsnConnector) Driver() driver.Driver {
	return c.d
}
