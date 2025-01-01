package utils

// Returns a new slice by applying f to each element in src.
// The core slices package doesn't have this functionality.
func MapSlice[I any, O any](src []I, f func(I) O) []O {
	dst := make([]O, len(src))
	for i, e := range src {
		dst[i] = f(e)
	}
	return dst
}

// Returns a new slice containing only the elements for which f returns true.
func FilterSlice[T any](src []T, f func(T) bool) []T {
	dst := make([]T, 0, len(src))
	for _, e := range src {
		if f(e) {
			dst = append(dst, e)
		}
	}
	return dst
}
