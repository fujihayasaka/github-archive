package http

import (
	"errors"
	"time"

	"github.com/github/go-stats"
	"github.com/sony/gobreaker"
)

// State is the state of the circuit breaker.
type State string

const (
	// StateOpen means that the circuit breaker is open.
	StateOpen State = "open"
	// StateHalfOpen means that the circuit breaker is half-open.
	StateHalfOpen State = "half-open"
	// StateClosed means that the circuit breaker is closed.
	StateClosed State = "closed"

	defaultTimeout      = 5 * time.Second
	defaultMaxRequests  = 20
	defaultFailureRatio = 0.5
	defaultInterval     = 60 * time.Second
)

// CircuitBreaker is an interface that allows us to accept different circuit
// breakers.
type CircuitBreaker interface {
	Execute(func() (interface{}, error)) (interface{}, error)
	State() State
}

// defaultBreaker is a circuit breaker with default settings.
type defaultBreaker struct {
	cb *gobreaker.CircuitBreaker
}

// breakerSettings defines the settings for the circuit breaker.
// If nil, default settings will be used.
// circuit breaker becomes half-open.
type breakerSettings struct {
	Interval      time.Duration
	Timeout       time.Duration
	MaxRequests   uint32
	FailureRatio  float64
	OnStateChange func(name string, from gobreaker.State, to gobreaker.State)
}

// CircuitBreakerOption is a function that sets a circuit breaker setting.
type CircuitBreakerOption func(*breakerSettings) error

// WithInterval sets the interval for the circuit breaker.
// Interval is the cyclic period of the closed state for the circuit breaker
// to clear the internal Counts.
func WithInterval(interval time.Duration) CircuitBreakerOption {
	return func(settings *breakerSettings) error {
		if interval == 0 {
			return errors.New("interval cannot be 0")
		}
		settings.Interval = interval
		return nil
	}
}

// WithTimeout sets the timeout for the circuit breaker.
// Timeout is the period of the open state, after which the state of the
// circuit breaker becomes half-open.
func WithTimeout(timeout time.Duration) CircuitBreakerOption {
	return func(settings *breakerSettings) error {
		if timeout == 0 {
			return errors.New("timeout cannot be 0")
		}
		settings.Timeout = timeout
		return nil
	}
}

// WithMaxRequests sets the maximum number of requests allowed to pass through
// when the circuit breaker is half-open.
func WithMaxRequests(maxRequests uint32) CircuitBreakerOption {
	return func(settings *breakerSettings) error {
		if maxRequests == 0 {
			return errors.New("max requests cannot be 0")
		}
		settings.MaxRequests = maxRequests
		return nil
	}
}

// WithFailureRatio sets the failure ratio for the circuit breaker.
func WithFailureRatio(failureRatio float64) CircuitBreakerOption {
	return func(settings *breakerSettings) error {
		if failureRatio == 0 {
			return errors.New("failure ratio cannot be 0")
		}
		if failureRatio >= 1 {
			return errors.New("failure ratio cannot be 1")
		}
		settings.FailureRatio = failureRatio
		return nil
	}
}

// WithStats sets the stats client to use for reporting circuit breaker state
// changes.
func WithStats(statter stats.Client) CircuitBreakerOption {
	return func(settings *breakerSettings) error {
		if statter == nil {
			statter = stats.NullStatter
		}

		settings.OnStateChange = func(name string, from gobreaker.State, to gobreaker.State) {
			statter.Counter("circuit_breaker.state_change", stats.Tags{"name": name, "from": from.String(), "to": to.String()}, 1)
		}

		return nil
	}
}

// NewCircuitBreaker returns a new circuit breaker with the provided settings.
func NewCircuitBreaker(opts ...CircuitBreakerOption) (CircuitBreaker, error) {
	settings := &breakerSettings{
		Interval:      defaultInterval,
		Timeout:       defaultTimeout,
		MaxRequests:   defaultMaxRequests,
		FailureRatio:  defaultFailureRatio,
		OnStateChange: func(name string, from gobreaker.State, to gobreaker.State) {},
	}

	for _, opt := range opts {
		if err := opt(settings); err != nil {
			return nil, err
		}
	}

	return &defaultBreaker{gobreaker.NewCircuitBreaker(gobreaker.Settings{
		Name:        "go-exception-reporter",
		Interval:    settings.Interval,
		Timeout:     settings.Timeout,
		MaxRequests: settings.MaxRequests,
		ReadyToTrip: func(counts gobreaker.Counts) bool {
			failureRatio := float64(counts.TotalFailures) / float64(counts.Requests)
			return counts.Requests >= settings.MaxRequests && failureRatio >= settings.FailureRatio
		},
		OnStateChange: settings.OnStateChange,
	})}, nil
}

// Execute executes the function f and returns its results, or an error if the
// circuit breaker is open.
func (s *defaultBreaker) Execute(f func() (interface{}, error)) (interface{}, error) {
	return s.cb.Execute(f)
}

// State returns the current state of the circuit breaker.
func (s *defaultBreaker) State() State {
	switch s.cb.State() {
	case gobreaker.StateClosed:
		return StateClosed
	case gobreaker.StateOpen:
		return StateOpen
	case gobreaker.StateHalfOpen:
		return StateHalfOpen
	default:
		return StateClosed
	}
}
