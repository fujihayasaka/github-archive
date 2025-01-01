package retry

import (
	"context"
	"errors"
	"fmt"
	"io"
	"net/http"
	"time"

	backoff "github.com/cenkalti/backoff/v4"
	"github.com/twitchtv/twirp"
)

// Forever returns a backoff instance that will exponentially backoff forever or
// until the context is canceled.
func Forever(ctx context.Context) backoff.BackOff {
	exp := backoff.NewExponentialBackOff()
	exp.MaxInterval = 20 * time.Second
	exp.MaxElapsedTime = 0
	return backoff.WithContext(exp, ctx)
}

func LowLatencyBackoff(ctx context.Context, retries uint64) backoff.BackOff {
	b := backoff.NewExponentialBackOff()

	// Set a lower initial interval to reduce latency
	b.InitialInterval = 100 * time.Millisecond
	return backoff.WithContext(backoff.WithMaxRetries(b, retries), ctx)
}

// DefaultBackOff returns a BackOff instance that:
//
// - Retries at most `retries` times
// - Stops when the context is canceled
// - Uses exponential backoff with no maximum duration
func DefaultBackOff(ctx context.Context, retries uint64) backoff.BackOff {
	exp := backoff.NewExponentialBackOff()
	exp.MaxElapsedTime = 0
	return backoff.WithContext(backoff.WithMaxRetries(exp, retries), ctx)
}

func DefaultConstBackOff(ctx context.Context, retries uint64) backoff.BackOff {
	return backoff.WithContext(backoff.WithMaxRetries(backoff.NewConstantBackOff(1*time.Second), retries), ctx)
}

// WithExceptions runs the operation that retries the specified number of times
// with an exponenial backoff strategy until the retries are exhausted or the
// context is cancelled; however if the error returned from the operation is one
// of those provided (as determined by errors.Is), the attempt will not be
// counted against the limit.
//
// This can be used to handle errors from a backend system that we want to retry
// until the backend becomes healthy again.
func WithExceptions(ctx context.Context, operation backoff.Operation, retries uint64, errors ...error) error {
	if len(errors) == 0 {
		panic("WithExceptions requires at least one error to except")
	}

	except := &Except{
		delegate:  DefaultBackOff(ctx, retries),
		forever:   Forever(ctx),
		errors:    errors,
		lastError: nil,
		ctx:       ctx,
	}

	exOp := func() error {
		err := operation()
		except.lastError = err
		return err
	}

	return backoff.Retry(exOp, except)
}

type Except struct {
	delegate  backoff.BackOff // delegate is the BackOff instance to be used by default
	forever   backoff.BackOff // forever is the BackOff instance to be used if lastError matches one of errors
	errors    []error         // errors is the slice of errors that should not be counted against the retry limit of delegate
	lastError error           // error is the last error returned by the operation, or nil
	ctx       context.Context // ctx is necessary to implement backoff.BackOffContext
}

// NextBackOff returns the amount of time to wait until the next attempt. If the
// last error from the operation returned an error in the errors slice, this
// method will return the next attempt using the forever BackOff instance;
// otherwise it will use the delegate.
func (e *Except) NextBackOff() time.Duration {
	if e.lastError != nil {
		for _, err := range e.errors {
			if errors.Is(e.lastError, err) {
				return e.forever.NextBackOff()
			}
		}
	}

	return e.delegate.NextBackOff()
}

func (e *Except) Reset() {
	e.delegate.Reset()
	e.forever.Reset()
	e.lastError = nil
}

func (e *Except) Context() context.Context {
	return e.ctx
}

// make sure Except implements BackOffContext
var _ backoff.BackOffContext = &Except{}

func CheckTwirpErrResponse(err error) error {
	if err == nil {
		return err
	}

	if errors.Is(err, context.Canceled) {
		return backoff.Permanent(err)
	}

	if twerr, ok := err.(twirp.Error); ok {
		switch twerr.Code() {
		case twirp.Internal:
			// retry internal errors (which include networking errors wrapped by the Twirp client)
			return err
		case twirp.Unavailable, twirp.ResourceExhausted, twirp.DeadlineExceeded:
			// Retry these
			return err
		default:
			// Anything else is a permanent failure
			return backoff.Permanent(err)
		}
	}

	return err
}

func IsTwirpNotFoundError(err error) bool {
	if twerr, ok := err.(twirp.Error); ok {
		return twerr.Code() == twirp.NotFound
	}
	return false
}

func IsTwirpDeadlineExceeded(err error) bool {
	if twerr, ok := err.(twirp.Error); ok {
		return twerr.Code() == twirp.DeadlineExceeded
	}
	return false
}

// checkHTTPResponse returns nil if the response was successful. If err is
// non-nil or the response has a retryable status code, an error is returned.
// If the response is not retryable, a backoff.Permament errror is returned.
// CheckHTTPResponse returns nil if the response was successful. If err is
// non-nil or the response has a retry-able status code, an error is returned.
// If the response is not retry-able, a backoff.Permanent error is returned.
func CheckHTTPResponse(resp *http.Response, err error) error {
	// Retry all errors (which probably indicate a network problem) except context.Canceled
	if err != nil {
		switch err {
		case context.Canceled:
			return backoff.Permanent(err)
		default:
			return err
		}
	}

	if resp == nil {
		panic("invariant violated: cannot have nil response and nil error")
	}

	if resp.StatusCode >= 200 && resp.StatusCode <= 299 {
		return nil
	}

	var details string
	if resp.Body != nil {
		errRespBytes, ioErr := io.ReadAll(resp.Body)
		if ioErr != nil {
			details = fmt.Sprintf("could not read response body: %v", ioErr)
		} else {
			details = fmt.Sprintf("%q", string(errRespBytes))
		}
	} else {
		details = "<no response body>"
	}
	respErr := fmt.Errorf("request failed with HTTP status code %d %s", resp.StatusCode, details)

	switch resp.StatusCode {
	case http.StatusGatewayTimeout, http.StatusRequestTimeout, http.StatusBadGateway, http.StatusServiceUnavailable, http.StatusInternalServerError, http.StatusTooManyRequests:
		return respErr
	default:
		return backoff.Permanent(respErr)
	}
}
