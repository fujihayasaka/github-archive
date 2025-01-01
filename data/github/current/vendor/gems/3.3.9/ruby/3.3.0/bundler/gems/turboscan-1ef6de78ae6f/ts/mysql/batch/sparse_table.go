// Package batch provides a way to batch process a table in MySQL.
package batch

import (
	"context"
	"fmt"
	"strings"

	"github.com/jinzhu/gorm"
	"github.com/pkg/errors"
	"golang.org/x/exp/constraints"
)

// SparseTable will call the given function as many times as necessary to process the entire table.
// The number of times is determined by the given step and the total number of rows in the table.
// The number of rows will be uniformly divided into batches of size step. The function will be
// called once for each batch. The function will be called with the start and end of the batch as
// arguments.
// You should use the MySQL BETWEEN operator to filter the table by the given column, or another
// method with the same semantics (>= min AND <= max).
func SparseTable[T constraints.Integer](ctx context.Context, db *gorm.DB, tableName, columnName string, step uint64, fn func(ctx context.Context, db *gorm.DB, start, end T) error) error {
	previousSparseID := uint64(0)

	for {
		nextSparseID, err := getNextSparseID(db, tableName, columnName, previousSparseID, step)
		if err != nil {
			return errors.Wrap(err, "failed to get next sparse id")
		}

		if nextSparseID == 0 {
			break
		}

		// We already included the "previousSparseID" in the last call, so we don't want to include it again.
		start := T(previousSparseID + 1)
		end := T(nextSparseID)

		err = fn(ctx, db, start, end)
		if err != nil {
			return errors.Wrap(err, fmt.Sprintf("partition %d-%d failed", previousSparseID, nextSparseID))
		}

		previousSparseID = nextSparseID
	}

	return nil
}

// getNextSparseID returns the next ID in the table that is `step` IDs away from the given lastID.
// If there are no more IDs in the table, it returns 0.
//
// Example query:
// SELECT COALESCE(MAX(repository_id), 0) FROM (SELECT repository_id FROM ts_repositories WHERE repository_id > 0 LIMIT 10000) AS x;
func getNextSparseID(db *gorm.DB, tableName, columnName string, lastID, step uint64) (uint64, error) {
	quotedColumnName := "`" + strings.ReplaceAll(columnName, "`", "``") + "`"

	subquery := db.Table(tableName).Select(columnName).Where(fmt.Sprintf("%s > ?", quotedColumnName), lastID).Limit(step).SubQuery()

	var result uint64
	if err := db.Raw(fmt.Sprintf("SELECT COALESCE(MAX(%s), 0) FROM ? AS x", quotedColumnName), subquery).Row().Scan(&result); err != nil {
		return 0, errors.Wrap(err, "error reading max id")
	}

	return result, nil
}
