package cache

import (
	"context"
	"time"
)

type ExpiringValue struct {
	Value  []byte
	Expiry time.Time
}

type ExpiringCache interface {
	Set(ctx context.Context, key string, value []byte, now time.Time, expiresIn time.Duration) (err error)
	Get(ctx context.Context, key string, now time.Time) (value *ExpiringValue, found bool, err error)
	// TODO: GetOrSet()
	// To best-effort-atomicly fill in values when they're missing.
	// Would serve as a single-flight mechanism, so that multiple
	// concurrent requests for the same key can be deduplicated to a
	// single call making it through, while the other ones wait to
	// share the result.
}
