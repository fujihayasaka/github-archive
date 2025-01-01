// Package transforms provides generic higher order functions for working with data.
package transforms

// Unique removes duplicates.
// It keeps the first occurrence of each element.
// It preserves the list order (stable).
func Unique[T comparable](items []T) []T {
	seen := make(map[T]struct{}, len(items))
	out := make([]T, 0, len(items))

	for _, item := range items {
		if _, ok := seen[item]; !ok {
			seen[item] = struct{}{}
			out = append(out, item)
		}
	}

	return out
}

// IndexBy creates a map using the result of fn as the key.
// It returns the last occurrence of each duplicate.
func IndexBy[K comparable, V any](items []V, fn func(V) K) map[K]V {
	out := make(map[K]V, len(items))
	for _, item := range items {
		out[fn(item)] = item
	}
	return out
}

// GroupBy groups elements using the result of transform as the key.
func GroupBy[K comparable, V any](items []V, fn func(V) K) map[K][]V {
	out := make(map[K][]V, len(items))
	for _, item := range items {
		key := fn(item)
		out[key] = append(out[key], item)
	}
	return out
}

// Map applies fn to each element in the slice and returns the result.
func Map[T, V any](items []T, fn func(T) V) []V {
	if items == nil {
		return nil
	}
	out := make([]V, 0, len(items))
	for _, item := range items {
		out = append(out, fn(item))
	}
	return out
}

// Flatten takes a series of lists and appends them together.
func Flatten[T any, S ~[]T](items []S) S {
	var out []T
	for _, item := range items {
		out = append(out, item...)
	}
	return out
}

// Filter returns the values where predicate returns true.
func Filter[T any](items []T, predicate func(T) bool) []T {
	result := make([]T, 0, len(items))

	for _, item := range items {
		if ok := predicate(item); ok {
			result = append(result, item)
		}
	}

	return result
}

// FilterMap combines Filter and Map into a single operation.
func FilterMap[T any, R any](items []T, fn func(T) (R, bool)) []R {
	result := make([]R, 0, len(items))

	for _, item := range items {
		if r, ok := fn(item); ok {
			result = append(result, r)
		}
	}

	return result
}

// MapUnique combines Map and Unique into a single operation
func MapUnique[T any, R comparable](items []T, fn func(T) R) []R {
	return Unique(Map(items, fn))
}

// BatchMap applies fn to each element in the slice and returns the result in batches of provided size.
func BatchMap[T, V any, S ~[]T](items S, size int, fn func(T) V) [][]V {
	batches := batchSlice(items, size)
	var out [][]V
	for _, batch := range batches {
		out = append(out, Map(batch, fn))
	}
	return out
}

func batchSlice[T any, S ~[]T](items S, size int) [][]T {
	if size == 0 {
		return nil
	}
	out := make([][]T, 0, len(items)+1)

	for i := 0; i < len(items); i += size {
		j := i + size
		if j > len(items) {
			j = len(items)
		}
		out = append(out, items[i:j])
	}

	return out
}
