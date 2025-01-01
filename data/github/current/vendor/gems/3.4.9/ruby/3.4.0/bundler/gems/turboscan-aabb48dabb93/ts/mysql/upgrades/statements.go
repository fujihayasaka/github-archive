package upgrades

import "context"

// Statements returns a func that can be passed to Function and will act like a Batched migration, executing each
// statement in order before moving on to the next batch.
func Statements(stmts ...string) func(ctx context.Context, db DB, start, end uint64) error {
	return func(ctx context.Context, db DB, start, end uint64) error {
		for _, stmt := range stmts {
			_, err := db.ExecContext(ctx, stmt, start, end)
			if err != nil {
				return err
			}
		}
		return nil
	}
}
