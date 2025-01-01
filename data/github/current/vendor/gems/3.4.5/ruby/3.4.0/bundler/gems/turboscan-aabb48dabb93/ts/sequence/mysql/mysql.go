// Package mysql provides a non-volatile numeric sequence generator backed by mysql and partitioned by repository_id.
package mysql

import (
	"context"
	"database/sql"
	"fmt"

	"github.com/pkg/errors"
)

// MySQLSequence represents a sequence
// backed by MySQL to store its data
type MySQLSequence struct {
	db        *sql.DB
	tableName string
	repoID    uint64
}

var updateSeqSQL = `
INSERT INTO %s
  (repository_id, number, created_at, updated_at)
VALUES
  (?, ?, NOW(), NOW())
ON DUPLICATE KEY UPDATE
  number = LAST_INSERT_ID(number + ?),
  updated_at = NOW()
`

func New(tableName string, repoID uint64, db *sql.DB) *MySQLSequence {
	return &MySQLSequence{
		tableName: tableName,
		repoID:    repoID,
		db:        db,
	}
}

// Next increment the counter and return it
func (s *MySQLSequence) Next(context context.Context) (uint32, error) {
	return s.Incr(context, 1)
}

// Incr increment the sequence by count and return the first free number
func (s *MySQLSequence) Incr(context context.Context, count uint32) (uint32, error) {
	// This query uses a few MySQL "hacks" to ensure that the incrementing
	// is done atomically and the value is returned. The first trick is done
	// using the `LAST_INSERT_ID` function. This allows us to manually set
	// the LAST_INSERT_ID returned by the query. Here we are able to set it
	// to the new value when an increment takes place, essentially allowing us
	// to do: `UPDATE...;SELECT value in a
	// single step.
	//
	// However the `LAST_INSERT_ID` trick is only used when the value is
	// updated. Upon a fresh insert we know the value was set to the specified number.
	//
	// This trick is copied wholesale from https://github.com/github/github-ds/blob/master/lib/github/kv.rb#L295

	result, err := s.db.ExecContext(context, fmt.Sprintf(updateSeqSQL, s.tableName), s.repoID, count, count)
	if err != nil {
		return 0, errors.Wrap(err, "updating sequence has failed")
	}

	rows, err := result.RowsAffected()
	if err != nil {
		return 0, errors.Wrap(err, "getting affected rows has failed")
	}

	switch rows {
	case 1:
		// If the number of RowsAffected is 1 then a new value was inserted
		// and we can just return 1, the first available free number
		return 1, nil
	case 2:
		// An update took place in which data changed. We use a hack to set
		// the last insert ID to be the new value.
		// This does not work in Vitess sharding mode
		id, err := result.LastInsertId()
		if err != nil {
			return 0, errors.Wrap(err, "fetching last insert id has failed")
		}

		// Return previous number + 1 (the first free number)
		return uint32(id) - count + 1, nil
	default:
		// No insert took place nor did any update occur. This means that
		// the value was not an integer thus not incremented.
		return 0, errors.New("updating sequence updated unexpected number of rows")
	}
}
