package jobapi

import (
	"context"
	"errors"
	"net/http"
	"strconv"
	"syscall"

	"github.com/Azure/azure-sdk-for-go/sdk/azcore"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/sweagentd/internal/capi"
	"github.com/github/sweagentd/internal/joberrors"
	"github.com/github/sweagentd/internal/jobservice"
	"github.com/github/sweagentd/internal/limiter"
	"github.com/github/sweagentd/internal/observability"
)

// truncatedError wraps an error and truncates its message to prevent overly verbose errors from being logged or reported.
type truncatedError struct {
	wrapped error
}

func (e *truncatedError) Error() string {
	return joberrors.Truncate(e.wrapped.Error(), joberrors.MaxErrorContentSize)
}

func (e *truncatedError) Unwrap() error {
	return e.wrapped
}

func (h *Handler) errorResponseWithError(ctx context.Context, w http.ResponseWriter, r *http.Request, logger log.Logger, err error, message string) error {
	// log the message and error, unless overridden
	loggedMessage := message
	loggedError := err

	returnedError := http.StatusText(http.StatusInternalServerError)
	statusCode := http.StatusInternalServerError

	// Azure Cosmos DB errors are far too verbose to bubble up and can,
	// so log it but only add info on the status code to the actual text
	var azErr *azcore.ResponseError
	var rateLimitErr *limiter.RateLimitError
	var abuseRateLimitErr *limiter.AbuseRateLimitError
	switch {
	case limiter.IsQueuedJobsExceededError(err):
		returnedError = "you have exceeded the maximum number of queued jobs"
		statusCode = http.StatusTooManyRequests
	case errors.As(err, &azErr):
		statusCode = azErr.StatusCode
		returnedError = http.StatusText(azErr.StatusCode)
	case errors.Is(err, context.Canceled):
		// Check to see if the context is cancelled from the top indicating the client went away, or if some context downstream canceled
		if ctx.Err() == context.Canceled {
			// No one is home to respond to anymore, but this is as good as any to close out gracefully with.
			statusCode = 499 // unofficial "context cancelled" status
			returnedError = "context cancelled"
		}
	case errors.Is(err, syscall.ECONNRESET):
		// No one is home to respond to anymore, but this is as good as any to close out gracefully with.
		statusCode = 499 // unofficial "context cancelled" status
		returnedError = "context cancelled"
	case capi.IsSessionNotFoundError(err):
		statusCode = http.StatusNotFound
		returnedError = err.Error()
	case capi.IsSessionUnauthorizedError(err):
		statusCode = http.StatusUnauthorized
		returnedError = err.Error()
	case capi.IsSessionRateLimitedError(err):
		statusCode = http.StatusTooManyRequests
		returnedError = err.Error()
	case errors.Is(err, jobservice.ErrNoModelAvailable):
		statusCode = http.StatusUnprocessableEntity
		returnedError = "no models available"
	case errors.Is(err, jobservice.ErrModelNotFound):
		statusCode = http.StatusBadRequest
		returnedError = "model is invalid"
	case errors.As(err, &rateLimitErr):
		// Primary rate limit indicates the rate limit exceeded for the specific user
		retryAfter := rateLimitErr.DurationUntilReset()
		w.Header().Set("Retry-After", strconv.Itoa(int(retryAfter.Seconds())))
		statusCode = http.StatusTooManyRequests
		returnedError = "primary rate limit exceeded"
	case errors.As(err, &abuseRateLimitErr):
		// Secondary/abuse rate limit indicates the rate limit regardless of users has been exceeded
		retryAfter := abuseRateLimitErr.DurationUntilReset()
		w.Header().Set("Retry-After", strconv.Itoa(int(retryAfter.Seconds())))
		statusCode = http.StatusServiceUnavailable
		returnedError = "secondary rate limit exceeded"
	case errors.Is(err, jobservice.ErrPullRequestExists):
		statusCode = http.StatusUnprocessableEntity
		returnedError = "pull request already exists"
	default:
		markedError := joberrors.MarkExistingError(err, message)
		returnedError = markedError.Error()
		statusCode = joberrors.StatusCodeFromMarkedError(markedError)
	}

	loggedError = &truncatedError{wrapped: loggedError}
	loggedMessage = joberrors.Truncate(loggedMessage, joberrors.MaxErrorMessageSize)
	returnedError = joberrors.Truncate(returnedError, joberrors.MaxErrorMessageSize)

	// Unmarked errors will be treated as internal server errors
	if statusCode < 500 {
		// Don't report 4xx status codes since they are likely user or transient errors, but log them.
		logger.WithError(loggedError).Error(loggedMessage)
	} else {
		h.obsv.LogAndReportError(ctx, loggedError, loggedMessage, observability.WithRequest(r))
	}

	return h.errorResponse(w, returnedError, statusCode)
}
