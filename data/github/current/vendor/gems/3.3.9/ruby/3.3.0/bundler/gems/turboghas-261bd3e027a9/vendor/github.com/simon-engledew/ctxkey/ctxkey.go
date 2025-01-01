package ctxkey

import (
	"context"
	"sync/atomic"
)

type contextKey uint64

var counter atomic.Uint64

type ContextKey[V any] struct {
	key          contextKey
	defaultValue V
}

func New[V any](defaultValue V) ContextKey[V] {
	return ContextKey[V]{
		key:          contextKey(counter.Add(1)),
		defaultValue: defaultValue,
	}
}

func (c ContextKey[V]) With(ctx context.Context, val V) context.Context {
	return context.WithValue(ctx, c.key, val)
}

func (c ContextKey[V]) Value(ctx context.Context) V {
	val, ok := ctx.Value(c.key).(V)
	if !ok {
		return c.defaultValue
	}
	return val
}
