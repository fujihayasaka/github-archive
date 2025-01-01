package utils

// Some returns true if at least one element in the array satisfies the test.
func Some[T any](arr []T, test func(T) bool) bool {
	for _, v := range arr {
		if test(v) {
			return true
		}
	}
	return false
}

// Every returns true if all elements in the array satisfy the test.
func Every[T any](arr []T, test func(T) bool) bool {
	for _, v := range arr {
		if !test(v) {
			return false
		}
	}
	return true
}

// Map applies the function to each element in the slice and returns a new slice.
func Map[T1, T2 any](arr []T1, fn func(T1) T2) []T2 {
	result := make([]T2, len(arr))
	for i, v := range arr {
		result[i] = fn(v)
	}
	return result
}

// Filter returns a new slice containing only the elements that satisfy the test function.
func Filter[T any](arr []T, test func(T) bool) []T {
	result := []T{}
	for _, v := range arr {
		if test(v) {
			result = append(result, v)
		}
	}
	return result
}

// Contains returns true if the slice contains the element.
func Contains[T comparable](arr []T, element T) bool {
	for _, v := range arr {
		if v == element {
			return true
		}
	}
	return false
}

// Keys returns a slice containing all keys from the map.
func Keys[T comparable, V any](set map[T]V) []T {
	result := make([]T, 0, len(set))
	for v := range set {
		result = append(result, v)
	}
	return result
}

// Values returns a slice containing all values from the map.
func Values[T comparable, V any](set map[T]V) []V {
	result := make([]V, 0, len(set))
	for _, v := range set {
		result = append(result, v)
	}
	return result
}

// FindIdx returns the first index for which the predicate is true, or -1 if none match.
func FindIdx[T any](arr []T, test func(T) bool) int {
	for i, v := range arr {
		if test(v) {
			return i
		}
	}
	return -1
}

// FindFirst returns, as the first value, the first element for which the predicate
// is true, or the zero value if none match. The second value is true if an element
// was found, and false otherwise.
func FindFirst[T any](arr []T, test func(T) bool) (T, bool) {
	idx := FindIdx(arr, test)
	if idx == -1 {
		var zero T
		return zero, false
	}
	return arr[idx], true
}

// GroupBy groups the elements in the slice by the key returned by the key function.
func GroupBy[T1, T2 comparable](arr []T1, keyFn func(T1) T2) map[T2][]T1 {
	result := make(map[T2][]T1)
	for _, v := range arr {
		key := keyFn(v)
		result[key] = append(result[key], v)
	}
	return result
}
