package jobapi

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"strings"

	"github.com/Azure/azure-sdk-for-go/sdk/azcore"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/sweagentd/internal/joberrors"
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
	if limiter.IsQueuedJobsExceededError(err) {
		return h.errorResponse(w, "you have exceeded the maximum number of queued jobs", http.StatusTooManyRequests)
	}

	// Azure Cosmos DB errors are far too verbose to bubble up and can,
	// so log it but only add info on the status code to the actual text
	statusCode := 0
	var azErr *azcore.ResponseError
	if errors.As(err, &azErr) {
		statusCode = azErr.StatusCode
		if message != "" {
			err = fmt.Errorf("%s: %s", message, strings.ToLower(http.StatusText(azErr.StatusCode)))
		} else {
			err = errors.New(strings.ToLower(http.StatusText(azErr.StatusCode)))
		}
	} else {
		err = joberrors.MarkExistingError(err, message)
		statusCode = joberrors.StatusCodeFromMarkedError(err)
	}

	err = &truncatedError{wrapped: err}
	message = joberrors.Truncate(message, joberrors.MaxErrorMessageSize)

	// Unmarked errors will be treated as internal server errors
	if statusCode < 500 {
		// Don't report 4xx status codes since they are likely user or transient errors, but log them.
		logger.WithError(err).Error(message)
	} else {
		h.obsv.LogAndReportError(ctx, err, message, observability.WithRequest(r))
	}

	return h.errorResponse(w, err.Error(), statusCode)
}
