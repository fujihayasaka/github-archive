package redis

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-mark"
	"github.com/github/go-stats"
	"github.com/github/sweagentd/internal/observability"
	"github.com/sony/gobreaker"
)

// Based on https://github.com/github/copilot-api/blob/main/pkg/redis/circuitbreaker.go

// RedisFailuresToTrip is the number of consecutive failures that will trip the circuit breaker.
const RedisFailuresToTrip = 10

// RedisResetInterval is the interval at which the circuit breaker will reset its error counts.
const RedisResetInterval = 60 * time.Second

// RedisOpenTimeout is the time the circuit breaker will wait before transitioning from open to half-open.
const RedisOpenTimeout = 10 * time.Second

// NewRedisCircuitBreaker creates a new circuit breaker for use with Redis.
// resetPeriod is how long the circuitbreaker will go before resetting its error
// counts. openPeriod represents the time before the circuitbreaker will wait
// before going from open to halfopen.
func NewRedisCircuitBreaker(obsv observability.Exporters, name string, resetPeriod, openTimeout time.Duration) *gobreaker.CircuitBreaker {
	// Redis circuit breaker
	cbSettings := gobreaker.Settings{
		Name:        fmt.Sprintf("RedisCircuitBreaker-%s", name),
		MaxRequests: 5,
		Interval:    resetPeriod,
		Timeout:     openTimeout,
		ReadyToTrip: func(counts gobreaker.Counts) bool {
			return counts.ConsecutiveFailures >= RedisFailuresToTrip
		},
		OnStateChange: func(name string, from, to gobreaker.State) {
			obsv.Statter.Gauge("redis_circuit_breaker_state", stats.Tags{"state": to.String(), "name": name}, 1)
			obsv.Logger.WithFields(
				kvp.String("breaker.name", name),
				kvp.String("breaker.state_from", from.String()),
				kvp.String("breaker.state_to", to.String()),
			).Warn("Redis circuit breaker state changed")
		},
		IsSuccessful: func(err error) bool {
			// A request to redis that doesn't return an error is successful.
			return err == nil ||
				// If it's a NotFound error, that's still "successful", it
				// just means there was no value to find.
				errors.Is(err, mark.ErrNotFound) ||
				// If it's a context canceled error, that's still "successful",
				// it just means the caller canceled the request. Note this is
				// different than the context exceeding its deadline.
				errors.Is(err, context.Canceled)
		},
	}
	return gobreaker.NewCircuitBreaker(cbSettings)
}
