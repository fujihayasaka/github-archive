package statter

import (
	"context"
	"sync"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
)

var (
	globalStatter *Statter
	mu            sync.Mutex
)

func GetStatter() *Statter {
	if globalStatter == nil {
		return NewStatter(stats.NullStatter)
	}

	return globalStatter
}

func GetBaseStatter() stats.Client {
	return GetStatter().base
}

func SetStatter(baseStatter stats.Client) {
	mu.Lock()
	globalStatter = NewStatter(baseStatter)
	mu.Unlock()
}

func Counter(ctx context.Context, key string, value int64, fields ...kvp.Field) {
	GetStatter().Counter(ctx, key, value, fields...)
}

func Increment(ctx context.Context, key string, fields ...kvp.Field) {
	GetStatter().Increment(ctx, key, fields...)
}

func Distribution(ctx context.Context, key string, value float64, fields ...kvp.Field) {
	GetStatter().Distribution(ctx, key, value, fields...)
}

func DistributionMs(ctx context.Context, key string, value time.Duration, fields ...kvp.Field) {
	GetStatter().DistributionMs(ctx, key, value, fields...)
}

func Gauge(ctx context.Context, key string, value int64, fields ...kvp.Field) {
	GetStatter().Gauge(ctx, key, value, fields...)
}

func Histogram(ctx context.Context, key string, value int64, fields ...kvp.Field) {
	GetStatter().Histogram(ctx, key, value, fields...)
}

func Timing(ctx context.Context, key string, value time.Duration, fields ...kvp.Field) {
	GetStatter().Timing(ctx, key, value, fields...)
}
