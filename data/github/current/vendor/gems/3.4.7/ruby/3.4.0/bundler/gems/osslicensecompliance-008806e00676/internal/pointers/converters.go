// Package pointers provides utilities for working with pointers in Go.
package pointers

// ValueOrZero returns the dereferenced pointer value or zero if nil.
func ValueOrZero[T any](p *T) T {
	var zero T
	if p == nil {
		return zero
	}
	return *p
}
