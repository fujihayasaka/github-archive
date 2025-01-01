package common

import (
	"context"

	"github.com/github/authnd/internal/common/diagnostics"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/sony/gobreaker"
)

// WithCircuitBreaker performs the provided 'do' function once (if it is allowed by the provided circuit breaker).
// If the circuit is open, the 'do' function will not be executed. If an error is returned by the 'do' function,
// that error is recorded by the circuit breaker based on the result of the provided 'errorIsTrippable' function.
// If 'errorIsTrippable' returns false, the error is ignored by the circuit breaker.
func WithCircuitBreaker(ctx context.Context, cb *gobreaker.CircuitBreaker, errorIsTrippable func(error) bool, do func() error) error {
	logger := diagnostics.Logger(ctx)

	var innerErr error
	_, cbErr := cb.Execute(func() (interface{}, error) {
		innerErr = do()
		if errorIsTrippable(innerErr) {
			// this errors count toward circuit trips
			logger.WithError(innerErr).Debug("counting error against circuit", kvp.String("gh.authnd.circuit_breaker.state", cb.State().String()))
			return nil, innerErr
		}
		// do not count the error towards the circuit trips
		return nil, nil
	})
	if cbErr != nil {
		// either the circuit is open or a "trippable" error was returned
		return cbErr
	}
	// no error or a non "trippable" error
	return innerErr
}

func NoopCircuitBreaker() *gobreaker.CircuitBreaker {
	return gobreaker.NewCircuitBreaker(gobreaker.Settings{
		ReadyToTrip: func(counts gobreaker.Counts) bool {
			// never trip the circuit
			return false
		},
	})
}
