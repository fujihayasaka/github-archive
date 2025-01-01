package gormbulk

import (
	"context"
	"sort"

	"github.com/github/turboscan/ts/gormext"

	"golang.org/x/exp/maps"
)

// Enable map keys to be retrieved in same order when iterating
func sortedKeys(val map[string]interface{}) []string {
	keys := maps.Keys(val)
	sort.Strings(keys)
	return keys
}

// execInChunks separates a slice into chunks of `size` and calls fn for each one.
func execInChunks[T any](ctx context.Context, objects []T, size int, fn func(chunk []T) error) error {
	return gormext.Chunks(ctx, size, len(objects), func(start, end int) error {
		return fn(objects[start:end])
	})
}
