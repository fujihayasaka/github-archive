package callcounter

import (
	"context"
	"fmt"
	"sync"

	"github.com/github/launch/pkg/mu/ctxkey"

	"github.com/github/launch/observability"
	"github.com/github/launch/observability/statter"
)

var key = ctxkey.New("callcounter")

type counter struct {
	name   string
	mutex  sync.Mutex
	counts map[string]int64
}

func newCounter(name string) *counter {
	return &counter{name: name, counts: map[string]int64{}}
}

func (c *counter) track(kind string) {
	c.mutex.Lock()
	defer c.mutex.Unlock()

	if v, ok := c.counts[kind]; ok {
		c.counts[kind] = v + 1
		return
	}
	c.counts[kind] = 1
}

func (c *counter) lock() func() {
	c.mutex.Lock()
	return func() {
		c.mutex.Unlock()
	}
}

// WithCounter creates a new context with a counter value initialized
func WithCounter(ctx context.Context, name string) context.Context {
	return context.WithValue(ctx, key, newCounter(name))
}

// ExternalCall increments the count for the kind passed in
func ExternalCall(ctx context.Context, kind string) {
	if v, ok := ctx.Value(key).(*counter); ok {
		v.track(kind)
	}
}

// get returns the call counts found in context.
func get(ctx context.Context) *counter {
	if v, ok := ctx.Value(key).(*counter); ok {
		return v
	}
	return newCounter("unknown_counter")
}

// Emit invokes a callback with, for each tracked call, the counter's name, the call's name
// and the number of times the call was counted.
func Emit(ctx context.Context, cb func(counterName, callName string, callCount int64)) {
	counter := get(ctx)
	unlock := counter.lock()
	defer unlock()
	for k, v := range counter.counts {
		cb(counter.name, k, v)
	}
}

// EmitHistogram sends the counts to datadog as a separate histogram per count type
func EmitHistogram(ctx context.Context, obs *observability.Observability, tags statter.Tags) {
	Emit(ctx, func(counterName, callName string, callCount int64) {
		name := fmt.Sprintf("call_count.%s", callName)
		t := tags.Merge(statter.Tags{"counter": counterName})
		obs.Distribution(ctx, name, t, float64(callCount))
	})
}
