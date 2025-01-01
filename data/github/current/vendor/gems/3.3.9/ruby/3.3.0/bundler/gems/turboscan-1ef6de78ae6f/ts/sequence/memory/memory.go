// Package memory defines a volatile numeric sequence generator used for testing.
package memory

import (
	"context"
	"sync/atomic"
)

// MemorySequence is a type that defines a
// in memory counter to be increamented.
// Note this is most likely only to be used in tests
// as in production we need to sync the number with already
// stored data.
// It should implement the Sequence interface
type MemorySequence struct {
	c atomic.Uint32
}

// Next increment the counter and return it
func (m *MemorySequence) Next(context context.Context) (uint32, error) {
	return m.Incr(context, 1)
}

// Incr increment the counter by count and return the first free number
func (m *MemorySequence) Incr(context context.Context, count uint32) (uint32, error) {
	v := m.c.Add(count)
	return v - count + 1, nil
}
