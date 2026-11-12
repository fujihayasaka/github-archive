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

// ZeroToNil returns a pointer to v if v is non-zero, or nil if v is the zero value.
func ZeroToNil[T comparable](v T) *T {
	var zero T
	if v == zero {
		return nil
	}
	return &v
}
