package storage

import (
	"context"
	"database/sql"
	"fmt"
	"reflect"

	"github.com/github/dependency-snapshots-api/internal/contextlogger"
	"github.com/github/dependency-snapshots-api/internal/features"
	"github.com/github/dependency-snapshots-api/internal/freno"
	"github.com/github/dependency-snapshots-api/internal/gitaccess"
	"github.com/github/dependency-snapshots-api/internal/repolocks"
	"github.com/github/dependency-snapshots-api/internal/snapshots"
	"github.com/github/dependency-snapshots-api/internal/storage/blob"
	"github.com/github/go-exceptions"
	"github.com/github/go-stats"
	"github.com/jmoiron/sqlx"
	"github.com/package-url/packageurl-go"
	"github.com/pkg/errors"
)

type Queryable interface {
	ExecContext(ctx context.Context, query string, args ...interface{}) (sql.Result, error)
	QueryxContext(ctx context.Context, query string, args ...interface{}) (*sqlx.Rows, error)
	QueryRowxContext(ctx context.Context, query string, args ...interface{}) *sqlx.Row
	Rebind(query string) string
	NamedExecContext(ctx context.Context, query string, arg interface{}) (sql.Result, error)
}

// ExecuteQuery is a convenience wrapper around the Queryable (e.g. transaction, connection) ExecContext. It should be used in cases where no rows
// are expected to be returned (i.e., inserts and updates). The sql.Result object contains the number of rows affected by the query and the
// last inserted ID (if any).
func ExecuteQuery(ctx context.Context, queryable Queryable, traceName string, query string, queryArgs ...interface{}) (sql.Result, error) {
	ctx, ender, _ := contextlogger.LogStartAndStop(ctx, "MySqlTracer", traceName)
	defer ender()

	res, err := queryable.ExecContext(ctx, query, queryArgs...)
	if err != nil {
		return nil, err
	}

	return res, nil
}

// NamedExec is a convenience wrapper around the Queryable (e.g. transaction, connection) ExecContext. It should be used in cases where you need sqlx's NamedExec functionality.
// The sql.Result object contains the number of rows affected by the query and the last inserted ID (if any).
func NamedExec(ctx context.Context, queryable Queryable, traceName string, query string, queryArgs interface{}) (sql.Result, error) {
	ctx, ender, _ := contextlogger.LogStartAndStop(ctx, "MySqlTracer", traceName)
	defer ender()

	res, err := queryable.NamedExecContext(ctx, query, queryArgs)
	if err != nil {
		return nil, err
	}

	return res, nil
}

// QueryRow is a convenience wrapper around the Queryable (e.g. transaction, connection) QueryRowxContext. It should be used in cases where a
// single row is expected to be returned. If multiple rows are returned from the query, the first row is used and the rest are ignored.
// `dest` must be a pointer to a struct, or else this function will return an error.
// The boolean return value indicates whether or not the row was found.
func QueryRow(ctx context.Context, queryable Queryable, dest interface{}, traceName string, query string, queryArgs ...interface{}) (bool, error) {
	if !isPointerToStruct(dest) {
		return false, errors.New("dest must be a pointer to a struct")
	}

	ctx, ender, _ := contextlogger.LogStartAndStop(ctx, "MySqlTracer", traceName)
	defer ender()

	row := queryable.QueryRowxContext(ctx, query, queryArgs...)
	err := row.Err()
	if err != nil {
		return false, err
	}
	err = row.StructScan(dest)
	if errors.Is(err, sql.ErrNoRows) {
		return false, nil
	} else if err != nil {
		return false, err
	}

	return true, nil

}

// ExecuteQueryAndReadRows is convenience wrapper for Queryable queries returning 0..n rows. It is currently unused in this codebase and due for a refactor
// to bring it in line with ExecuteQuery and QueryRow.
func ExecuteQueryAndReadRows(ctx context.Context, queryable Queryable, rowHandler func(*sqlx.Rows) error, traceName string, query string, queryArgs ...interface{}) error {
	ctx, ender, _ := contextlogger.LogStartAndStop(ctx, "MySqlTracer", traceName)
	defer ender()

	rows, err := queryable.QueryxContext(ctx, query, queryArgs...)
	if err != nil {
		return errors.Wrap(err, "initial query")
	}

	defer rows.Close()

	for rows.Next() {
		err := rowHandler(rows)
		if err != nil {
			return errors.Wrapf(err, "row handler")
		}
	}

	// it's not an error to receive no rows from the database
	if err != nil && !errors.Is(err, sql.ErrNoRows) {
		return errors.Wrap(err, "reading rows")
	}
	return nil
}

// QueryRows is a convenience wrapper around the Queryable (e.g. transaction, connection) QueryxContext. It should be used in cases where 0..n rows
// are expected to be returned. `dest` must be a pointer to a slice of structs, or else this function will return an error.
func QueryRows[Dest any](ctx context.Context, queryable Queryable, dest *[]Dest, traceName, query string, queryArgs ...interface{}) error {
	ctx, ender, _ := contextlogger.LogStartAndStop(ctx, "MySqlTracer", traceName)
	defer ender()

	rows, err := queryable.QueryxContext(ctx, query, queryArgs...)
	if err != nil {
		return fmt.Errorf("initial query: %v", err)
	}
	defer rows.Close()

	for rows.Next() {
		var d Dest
		err := rows.StructScan(&d)
		if err != nil {
			return fmt.Errorf("row handler: %v", err)
		}
		*dest = append(*dest, d)
	}

	return nil
}

type MySQLSnapshotsAdapter struct {
	AdapterOptions
}

type AdapterOptions struct {
	DB *sqlx.DB
	// blobClient is a client that can access blob storage. at the time of this writing,
	// blobClient will be null when blob storage is not enabled for a given environment.
	BlobClient blob.BlobClient
	Git        gitaccess.Client
	Freno      *freno.FrenoClient
	Features   features.Client
	RepoLocker repolocks.Service
	Statter    stats.Client
	Reporter   *exceptions.Reporter
	// Whether we should store blobs in Azure Blob Store
	ShouldStoreBlobsInAzure bool
	// Whether we should store or delete snapshots out of canonicity.
	ShouldStoreHistoricalSnapshots bool
	// Whether or not we should store blobs in the SQL DB instead of blob storage
	ShouldStoreBlobsInDatabase bool
}

func NewAdapter(options AdapterOptions) snapshots.StorageAdapter {
	return &MySQLSnapshotsAdapter{options}
}

func (a *AdapterOptions) GetReporter() *exceptions.Reporter {
	if a.Reporter != nil {
		return a.Reporter
	} else {
		return exceptions.NullReporter
	}
}

// getDependencyLocatorPURL returns a PURL that contains a subset of the input URL fields.
// Generally, we start with a dependency locator and then compare the full PURL after the locator provides a hit.
func getDependencyLocatorPURL(purl packageurl.PackageURL) *packageurl.PackageURL {
	return packageurl.NewPackageURL(purl.Type, purl.Namespace, purl.Name, "", packageurl.Qualifiers{}, "")
}

// This PURL is what we will store in the database. It is the same as the dependencyLocatorPURL except it also contains the version.
func getStrippedPURLWithVersion(purl packageurl.PackageURL) *packageurl.PackageURL {
	return packageurl.NewPackageURL(purl.Type, purl.Namespace, purl.Name, purl.Version, packageurl.Qualifiers{}, "")
}

func isPointerToStruct(v interface{}) bool {
	vType := reflect.TypeOf(v)

	return vType.Kind() == reflect.Ptr &&
		!reflect.ValueOf(v).IsNil() &&
		vType.Elem().Kind() == reflect.Struct
}
