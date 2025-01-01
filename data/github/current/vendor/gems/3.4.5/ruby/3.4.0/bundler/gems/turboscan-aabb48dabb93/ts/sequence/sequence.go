// Package sequence provides an interface for generating numeric sequences.
package sequence

import (
	"context"
)

// Sequence defines the functions a Sequence implementation
// can have. The Sequence is used when generating a numeric sequence
// for a given context(i.e. Repository)
type Sequence interface {
	// Next increment the counter and return it
	Next(context context.Context) (uint32, error)
	// Incr inrements the counter by count and returns the first free number
	Incr(context context.Context, count uint32) (uint32, error)
}
