package statter

import (
	"context"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	"github.com/github/hosted-compute-ims/internal/telemetry/stash"
)

type Statter struct {
	base stats.Client
}

func NewStatter(base stats.Client) *Statter {
	return &Statter{
		base: base,
	}
}

func (s *Statter) Counter(ctx context.Context, key string, value int64, fields ...kvp.Field) {
	tags := s.collectStatsTags(ctx, fields)
	s.base.Counter(key, tags, value)
}

func (s *Statter) Increment(ctx context.Context, key string, fields ...kvp.Field) {
	tags := s.collectStatsTags(ctx, fields)
	s.base.Counter(key, tags, 1)
}

func (s *Statter) Distribution(ctx context.Context, key string, value float64, fields ...kvp.Field) {
	tags := s.collectStatsTags(ctx, fields)
	s.base.Distribution(key, tags, value)
}

func (s *Statter) DistributionMs(ctx context.Context, key string, value time.Duration, fields ...kvp.Field) {
	tags := s.collectStatsTags(ctx, fields)
	s.base.DistributionMs(key, tags, value)
}

func (s *Statter) Gauge(ctx context.Context, key string, value int64, fields ...kvp.Field) {
	tags := s.collectStatsTags(ctx, fields)
	s.base.Gauge(key, tags, value)
}

func (s *Statter) Histogram(ctx context.Context, key string, value int64, fields ...kvp.Field) {
	tags := s.collectStatsTags(ctx, fields)
	s.base.Histogram(key, tags, value)
}

func (s *Statter) Timing(ctx context.Context, key string, value time.Duration, fields ...kvp.Field) {
	tags := s.collectStatsTags(ctx, fields)
	s.base.Timing(key, tags, value)
}

func (s *Statter) collectStatsTags(ctx context.Context, newFields []kvp.Field) stats.Tags {
	fields := stash.StatterFieldsFromContext(ctx)
	if len(newFields) > 0 {
		fields = append(fields, newFields...)
	}

	return stash.KvpFieldsToMap(fields)
}
