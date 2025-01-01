// Package data contains methods for accessing data in the database.
package data

import (
	"context"
	"database/sql"
	"database/sql/driver"
	"time"

	"github.com/github/go-stats"
	"github.com/github/turboghas/internal/fromctx"
	"github.com/github/turboghas/internal/mysql_dual"
	"github.com/pkg/errors"
	"google.golang.org/protobuf/types/known/timestamppb"
)

type UserID uint64
type RepositoryID uint64
type BusinessID uint64

type Data struct {
	db *mysql_dual.Connection
}

func New(db *mysql_dual.Connection) *Data {
	return &Data{
		db: db,
	}
}

func PtrTo[T any](t T) *T {
	return &t
}

func Timestamp(t **timestamppb.Timestamp) interface {
	sql.Scanner
	driver.Valuer
} {
	return timestamppbType{value: t}
}

type timestamppbType struct {
	value **timestamppb.Timestamp
}

func (t timestamppbType) Scan(val any) error {
	*t.value = timestamppb.New(val.(time.Time))
	return nil
}

func (t timestamppbType) Value() (driver.Value, error) {
	if t.value == nil {
		return nil, nil
	}
	return (*t.value).AsTime(), nil
}

func rowsAffected(result sql.Result) int64 {
	count, err := result.RowsAffected()
	if err != nil {
		return 0
	}
	return count
}

func pluckBool(row *sql.Row) (bool, error) {
	var v bool
	err := row.Scan(&v)
	if errors.Is(err, sql.ErrNoRows) {
		return v, nil
	}
	return v, err
}

type Inserter interface {
	Insert(stmt string, args ...any) error
}

type Updater interface {
	Update(stmt string, args ...any) Inserter
}

type Selector interface {
	Select(stmt string, args ...any) Updater
	Touch(stmt string, args ...any) Updater
}

// upserterDone is the noop type for Upserter
// It wraps errors if encountered, and replaces the method chaining calls with noops.
type upserterDone struct {
	err error
}

func (u upserterDone) Insert(_ string, _ ...any) error {
	return u.err
}

func (u upserterDone) Update(_ string, _ ...any) Inserter {
	return u
}

type upserter struct {
	ctx context.Context
	db  *mysql_dual.Connection
}

func Upserter(ctx context.Context, db *mysql_dual.Connection, tags stats.Tags) Selector {
	return &upserter{ctx: fromctx.Statter.With(ctx, fromctx.Statter.Value(ctx).WithTags(tags)), db: db}
}

// Select checks if there is any work to do using the provided stmt.
func (u *upserter) Select(stmt string, args ...any) Updater {
	exists, err := pluckBool(u.db.Replica.QueryRowContext(u.ctx, stmt, args...))
	if exists || err != nil {
		if err == nil {
			fromctx.Statter.Value(u.ctx).Counter("data.match", nil, 1)
		}

		// errors.Wrap returns nil if the error is nil, giving us upserterDone{nil}
		return upserterDone{errors.Wrap(err, "failed to select row")}
	}
	return u
}

// Touch updates updated_at if the row was the same
func (u *upserter) Touch(stmt string, args ...any) Updater {
	res, err := u.db.Primary.ExecContext(u.ctx, stmt, args...)
	if err != nil || rowsAffected(res) > 0 {
		if err == nil {
			fromctx.Statter.Value(u.ctx).Counter("data.match", nil, 1)
		}

		// errors.Wrap returns nil if the error is nil, giving us upserterDone{nil}
		return upserterDone{errors.Wrap(err, "failed to touch row")}
	}
	return u
}

// Update should be passed a SQL UPDATE SET WHERE stmt.
func (u *upserter) Update(stmt string, args ...any) Inserter {
	res, err := u.db.Primary.ExecContext(u.ctx, stmt, args...)

	if err != nil {
		return upserterDone{errors.Wrap(err, "failed to update row")}
	}

	// this check depends on the ClientFoundRows option being set
	updated := rowsAffected(res)
	switch updated {
	case 0:
		return u
	case 1:
		fromctx.Statter.Value(u.ctx).Counter("data.update", nil, 1)
		return upserterDone{nil}
	default:
		return upserterDone{errors.Errorf("update modified %d rows instead of one", updated)}
	}
}

// Insert performs the final insert if needed, returning any error encountered in prior method chaining.
// To avoid race conditions the provided stmt should normally be a SQL upsert statement.
func (u *upserter) Insert(stmt string, args ...any) error {
	res, err := u.db.Primary.ExecContext(u.ctx, stmt, args...)

	if err == nil {
		switch rowsAffected(res) {
		case 1:
			fromctx.Statter.Value(u.ctx).Counter("data.insert", nil, 1)
		case 2:
			fromctx.Statter.Value(u.ctx).Counter("data.upsert", nil, 1)
		}
	}

	return errors.Wrap(err, "failed to upsert row")
}
