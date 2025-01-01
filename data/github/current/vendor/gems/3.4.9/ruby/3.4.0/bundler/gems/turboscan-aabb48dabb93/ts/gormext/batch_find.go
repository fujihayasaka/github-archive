package gormext

import (
	"context"

	"github.com/jinzhu/gorm"
)

// Chunks calls fn with start and end indexes for each chunk of `size` up to `limit`.
// `end` and `limit` are exclusive; `limit` typically being the len() of a slice and `end` representing
// the end of a range, e.g: `slice[start:end]`
func Chunks(ctx context.Context, size, limit int, fn func(start int, end int) error) error {
	for start, end := 0, size; start < limit; start, end = end, end+size {
		if ctx.Err() != nil {
			return ctx.Err()
		}
		// reduce end to not go beyond the limit
		if end > limit {
			end = limit
		}
		err := fn(start, end)
		if err != nil {
			return err
		}
	}

	return nil
}

// FindInBatchesOf runs findFunc for chunks of ids, appending the results and returning them together
func FindInBatchesOf[T any, V any](ctx context.Context, size int, ids []V, findFunc func(start, end int) *gorm.DB) ([]T, error) {
	var items []T
	var rows []T
	return items, Chunks(ctx, size, len(ids), func(start, end int) error {
		err := findFunc(start, end).Find(&rows).Error
		items = append(items, rows...)
		return err
	})
}
