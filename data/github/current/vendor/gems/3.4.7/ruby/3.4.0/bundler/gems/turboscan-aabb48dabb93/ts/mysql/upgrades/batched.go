package upgrades

import (
	"context"
)

// Batched runs the given SQL statement against batches of ids in
// turn. The table must have a primary key named 'id' and the given statement
// must have two placeholder parameters to be replaced by the two endpoints of
// the interval.
//
// Example statement:
//
//	UPDATE foo SET bar = baz + 1 WHERE id BETWEEN ? AND ? AND bar < baz
func (t *transitions) Batched(tableName string, stmt string) Builder {
	return t.Function(tableName, func(ctx context.Context, db DB, start, end uint64) error {
		_, err := db.ExecContext(ctx, stmt, start, end)
		return err
	})
}
