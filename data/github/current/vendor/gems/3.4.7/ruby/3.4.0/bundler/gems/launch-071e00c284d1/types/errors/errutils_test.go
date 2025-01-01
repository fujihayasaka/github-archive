package errors

import (
	"testing"
	"time"

	errs "github.com/pkg/errors"
	"github.com/stretchr/testify/assert"
	"github.com/twitchtv/twirp"

	"github.com/github/launch/pkg/panicmultierrgroup"
	svcerr "github.com/github/launch/services/errors"
	"github.com/github/launch/workflowbuild/azp/azperrors"
)

func Test_IsRetryable(t *testing.T) {
	tests := []struct {
		name        string
		err         error
		isRetryable bool
	}{
		{
			name:        "Basic string error",
			err:         errs.New("some error"),
			isRetryable: false,
		},
		{
			name:        "Explicitly unretryable error",
			err:         &testPermanentError{errs.New("400 Invalid Workflow Syntax")},
			isRetryable: false,
		},
		{
			name:        "Retryable error",
			err:         &testRetryableError{errs.New("database timeout")},
			isRetryable: true,
		},
		{
			name:        "Error chain containing retryable error",
			err:         errs.Wrap(errs.Wrap(&testRetryableError{errs.New("database timeout")}, "failed to check for existing workflow build"), "failed to queue a build for awesome.yml"),
			isRetryable: true,
		},
		{
			name:        "A RetryableDurationError",
			err:         NewRetryableDuration("My keys are around here somewhere", 90*time.Second),
			isRetryable: true,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(tt *testing.T) {
			assert.Equal(t, tc.isRetryable, IsRetryable(tc.err))
		})
	}
}

type testPermanentError struct {
	error
}

func (p *testPermanentError) IsRetryable() bool {
	return false
}

type testRetryableError struct {
	error
}

func (p *testRetryableError) IsRetryable() bool {
	return true
}

type testSystemError struct {
	error
}

func (p *testSystemError) IsUserError() bool {
	return false
}

type testUserError struct {
	error
}

func (p *testUserError) IsUserError() bool {
	return true
}

func Test_IsUserError(t *testing.T) {
	emptyErrGroup := &panicmultierrgroup.Group{}
	emptyErrors := emptyErrGroup.Wait()

	singleUserErrGroup := &panicmultierrgroup.Group{}
	singleUserErrGroup.Go(func() error {
		return NewUserError("Email not verified")
	})
	singleUserMultiError := singleUserErrGroup.Wait()

	userErrGroup := &panicmultierrgroup.Group{}
	userErrGroup.Go(func() error {
		return NewUserError("Syntax error in workflow A")
	})
	userErrGroup.Go(func() error {
		return NewUserError("Syntax error in workflow B")
	})
	userMultiError := userErrGroup.Wait()

	errGroup := &panicmultierrgroup.Group{}
	errGroup.Go(func() error {
		return NewUserError("Syntax error in workflow A")
	})
	errGroup.Go(func() error {
		return errs.New("Database error")
	})
	multierror := errGroup.Wait()

	tests := []struct {
		name        string
		err         error
		isUserError bool
	}{
		{
			name:        "nil error",
			err:         nil,
			isUserError: false,
		},
		{
			name:        "Basic string error",
			err:         errs.New("some error"),
			isUserError: false,
		},
		{
			name:        "Explicitly not a user error",
			err:         &testSystemError{errs.New("System error")},
			isUserError: false,
		},
		{
			name:        "Error implementing IsUserError interface",
			err:         &testUserError{errs.New("Email not verified")},
			isUserError: true,
		},
		{
			name:        "UserError",
			err:         NewUserError("Email not verified"),
			isUserError: true,
		},
		{
			name:        "AZP Syntax Error",
			err:         azperrors.NewInvalidSyntaxError("Unknown field job"),
			isUserError: true,
		},
		{
			name:        "Error chain caused by user error",
			err:         errs.Wrap(errs.Wrap(NewUserError("Email not verified"), "failed to check for existing workflow build"), "failed to queue a build for awesome.yml"),
			isUserError: true,
		},
		{
			name:        "Empty error group",
			err:         emptyErrors,
			isUserError: false,
		},
		{
			name:        "Single user multierror",
			err:         singleUserMultiError,
			isUserError: true,
		},
		{
			name:        "User multierror",
			err:         userMultiError,
			isUserError: true,
		},
		{
			name:        "Multierror with non-user error",
			err:         multierror,
			isUserError: false,
		},
		{
			name:        "Internal error",
			err:         NewInternalError(errs.New("Internal error")),
			isUserError: false,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(tt *testing.T) {
			assert.Equal(t, tc.isUserError, IsUserError(tc.err))
		})
	}
}

func Test_IsNotFoundError(t *testing.T) {
	tests := []struct {
		name     string
		err      error
		expected bool
	}{
		{
			name:     "Basic string error",
			err:      errs.New("some error"),
			expected: false,
		},
		{
			name:     "NotFoundError type",
			err:      NewNotFoundError(errs.New("i do not haz cheeseburger")),
			expected: true,
		},
		{
			name:     "Error chain containing NotFoundError type",
			err:      errs.Wrap(errs.Wrap(NewNotFoundError(errs.New("i do not haz fries")), "failed to check for existing workflow build"), "failed to queue a build for awesome.yml"),
			expected: true,
		},
		{
			name:     "Error chain containing GraphQL NotFoundError type",
			err:      errs.Wrap(NewGraphQLError(NewNotFoundError(errs.New("i do not haz shake"))), "error fetching invocation data"),
			expected: true,
		},
		{
			name:     "twirp.Error with NotFound code",
			err:      twirp.NotFoundError("Excuses not found"),
			expected: true,
		},
		{
			name:     "Error chain containing NotFoundError type",
			err:      errs.Wrap(errs.Wrap(twirp.NotFoundError("Excuses not found"), "failed to check for existing workflow build"), "failed to queue a build for awesome.yml"),
			expected: true,
		},
		{
			name:     "twirp.Error with some other code",
			err:      twirp.RequiredArgumentError("number_of_sparkles required."),
			expected: false,
		},
		{
			name:     "gRPC Not Found error",
			err:      svcerr.NewNotFoundError("Not found"),
			expected: true,
		},
		{
			name:     "http error with 404 status code",
			err:      &httpError{code: 404},
			expected: true,
		},
		{
			name:     "http error with a different status code",
			err:      &httpError{code: 403},
			expected: false,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(tt *testing.T) {
			assert.Equal(t, tc.expected, IsNotFoundError(tc.err), tc.name)
		})
	}
}

type testRateLimitedError struct {
	error
}

func (r *testRateLimitedError) RateLimited() bool {
	return true
}

func Test_IsRateLimitError(t *testing.T) {
	tests := []struct {
		name     string
		err      error
		expected bool
	}{
		{
			name:     "nil error",
			err:      nil,
			expected: false,
		},
		{
			name:     "Basic string error",
			err:      errs.New("some error"),
			expected: false,
		},
		{
			name:     "RateLimited type",
			err:      &testRateLimitedError{errs.New("rate limited")},
			expected: true,
		},
		{
			name:     "Error chain containing RateLimited type",
			err:      errs.Wrap(errs.Wrap(&testRateLimitedError{errs.New("rate limited")}, "inner failure"), "outer failure"),
			expected: true,
		},
		{
			name:     "twirp.Error with ResourceExhausted code",
			err:      twirp.NewError(twirp.ResourceExhausted, "Excuses not found"),
			expected: true,
		},
		{
			name:     "Error chain containing ResourceExhausted type",
			err:      errs.Wrap(errs.Wrap(twirp.NewError(twirp.ResourceExhausted, "Excuses not found"), "inner failure"), "outer failure"),
			expected: true,
		},
		{
			name:     "twirp.Error with some other code",
			err:      twirp.RequiredArgumentError("number_of_sparkles required."),
			expected: false,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(tt *testing.T) {
			assert.Equal(t, tc.expected, IsRateLimitError(tc.err), tc.name)
		})
	}
}

func Test_FindRetryableDurationErrors(t *testing.T) {
	errGroup := &panicmultierrgroup.Group{}
	errGroup.Go(func() error {
		return NewRetryableDuration("I lost my keys", 90*time.Second)
	})
	errGroup.Go(func() error {
		return errs.New("Database error")
	})
	errGroup.Go(func() error {
		return NewRetryableDuration("I lost my wallet", 15*time.Minute)
	})
	multierror := errGroup.Wait()

	tests := []struct {
		name      string
		err       error
		durations []time.Duration
	}{
		{
			name:      "Basic string error",
			err:       errs.New("some error"),
			durations: []time.Duration{},
		},
		{
			name:      "A RetryableDurationError",
			err:       NewRetryableDuration("My keys are around here somewhere", 90*time.Second),
			durations: []time.Duration{90 * time.Second},
		},
		{
			name:      "A multiError with two durations",
			err:       multierror,
			durations: []time.Duration{90 * time.Second, 15 * time.Minute},
		},
		{
			name:      "A wrapped multiError with two durations",
			err:       errs.Wrap(errs.Wrap(multierror, "Error leaving the house"), "Error going to dinner"),
			durations: []time.Duration{90 * time.Second, 15 * time.Minute},
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(tt *testing.T) {
			durations := []time.Duration{}

			FindRetryableDurationErrors(tc.err, func(dErr RetryableDurationError) {
				durations = append(durations, dErr.RetryDuration())
			})

			assert.ElementsMatch(t, tc.durations, durations)
		})
	}
}
