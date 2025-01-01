// Package querier provides a composable way to enrich a database access layer.
package querier

import (
	"context"
	sqlpkg "database/sql"

	"github.com/Masterminds/squirrel"
	"github.com/jmoiron/sqlx"

	"github.com/github/notifyd/internal/pkg/errors"
)

/*
Querier exposes an interface for executing SQL queries against a store. That store can be anything
from a read-only database connection to a transaction as long as it implements the right interfaces
(read slqx's documentation for more information).

It is meant to be a composable way to enrich our database access layer with common functionalities
needed on all repositories.

For now (December-2022) it includes 2 implementations:

- base: provides simple database access for basic DB operations and encapsulates error management.
- retrier: privides retries for known transient errors of the DB layer.

Implementations are composable and can be extended and customized as needed.

A full example might look like this:

	type RepoQueries struct{}

	func (q RepoQueries) findByIDs(ids []int64) squirrel.Sqlizer {
		return squirrel.Select("*").From("some_table").Where(squirrel.Eq{"id": ids})
	}

	type Repo struct {
		Querier
		queries RepoQueries
	}

	func NewRepo(clock clock.Clock, logger logs.Logger) Repo {
		querier := NewRetrier(New(), clock, logger)

		return Repo{querier, RepoQueries{}}
	}

	func (r Repo) get(ctx context.Context, store sqlx.QueryerContext, ids []int64) error {
		var elements []Model
		if err := r.Select(ctx, store, &elements, r.queries.findByIDs(ids)); err != nil {
			return elements, errors.Wrap(err, "fetching models")
		}

		return elements, nil
	}

Model is an example type that would serve as a DTO for the result of the query.
*/
type Querier interface {
	Delete(ctx context.Context, store sqlx.ExecerContext, query squirrel.Sqlizer) error
	Select(ctx context.Context, store sqlx.QueryerContext, dst interface{}, query squirrel.Sqlizer) error
	Insert(ctx context.Context, store sqlx.ExecerContext, query squirrel.Sqlizer) (Result, error)
	AutoIncrementStep(ctx context.Context, txx *sqlx.Tx) (int64, error)
}

// New creates a new querier.
func New() Querier {
	return base{}
}

// base is the bare minimum querier implementation. It just receives a query in squirrel format and
// sends it to the provided database store.
type base struct{}

func (r base) Delete(ctx context.Context, store sqlx.ExecerContext, query squirrel.Sqlizer) error {
	sql, args, err := query.ToSql()
	if err != nil {
		return errors.Wrap(err, "building query")
	}

	if _, err := store.ExecContext(ctx, sql, args...); err != nil {
		return errors.Wrap(err, "deleting")
	}

	return nil
}

func (r base) Select(ctx context.Context, store sqlx.QueryerContext, dst interface{}, query squirrel.Sqlizer) error {
	sql, args, err := query.ToSql()
	if err != nil {
		return errors.Wrap(err, "building query")
	}

	err = sqlx.SelectContext(ctx, store, dst, sql, args...)
	if err != nil {
		return errors.Wrap(err, "fetching")
	}

	return nil
}

func (r base) Insert(ctx context.Context, store sqlx.ExecerContext, query squirrel.Sqlizer) (Result, error) {
	sql, args, err := query.ToSql()
	if err != nil {
		return Result{}, errors.Wrap(err, "building query")
	}

	result, err := store.ExecContext(ctx, sql, args...)
	if err != nil {
		return Result{}, errors.Wrap(err, "inserting")
	}

	return Result{result}, nil
}

type autoIncrementStep struct {
	Name  string `db:"Variable_name"`
	Value int64  `db:"Value"`
}

func (r base) AutoIncrementStep(ctx context.Context, txx *sqlx.Tx) (int64, error) {
	row := txx.QueryRowxContext(ctx, "SHOW VARIABLES where Variable_name = ?", "auto_increment_increment")

	var step autoIncrementStep
	err := row.StructScan(&step)
	if err != nil {
		return 0, errors.Wrap(err, "fetching auto increment")
	}

	return step.Value, nil
}

// Result abstracts calculating the IDs of the last batch inserted elements.
//
// It does so by using LastInsertID and RowsAffected as on batch inserts it is guaranteed that they
// will be consecutive.
type Result struct {
	sqlpkg.Result
}

// EachID iterates over each one of the last inserted ids on a batch insert. The iterator function
// receives an index of the element that has been inserted and the corresponding ID.
//
// For example, if you insert 3 new subscriptions and they end up being IDs 100, 101 and 102 the
// iterator will be called with:
//
// - idx: 0, id: 100
// - idx: 1, id: 101
// - idx: 2, id: 102
//
// It is confusing, I know, that we use `LastInsertId` as the base for this calculation, I know...
// but that's how Go's `Result` works for MySQL.
//
// I was confused by this myself and I confirmed it with the results in the database.
func (r Result) EachID(iter func(idx int64, id int64), autoIncrementStep int64) error {
	firstID, err := r.LastInsertId()
	if err != nil {
		return err
	}

	offset, err := r.RowsAffected()
	if err != nil {
		return err
	}

	for idx := int64(0); idx < offset; idx++ {
		iter(idx, firstID+idx*autoIncrementStep)
	}

	return nil
}
