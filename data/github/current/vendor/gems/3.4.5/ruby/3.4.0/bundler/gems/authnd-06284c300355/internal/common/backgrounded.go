package common

import (
	"context"
	"time"

	"github.com/github/authnd/internal/common/diagnostics"
	"github.com/github/go-ctxutil"
	"github.com/github/go-stats"
	"github.com/pkg/errors"
)

// WithBackgroundedOperation runs the given operation in a goroutine with a context that is detached from the caller with a new timeout. Any muted errors
// provided with be statted but not sent to sentry.
// The function is NOT executed in a goroutine if detected that we are running in an integration test
func WithBackgroundedOperation(ctx context.Context, operationName string, operation func(ctx context.Context) error, timeout time.Duration, mutedErrors ...error) {
	if diagnostics.IsIntegrationTest(ctx) {
		operationWithErrorHandling(ctx, operationName, operation, mutedErrors...)
		return
	}

	detachedCtx, detachedCtxCancel := context.WithTimeout(ctxutil.DetachedCancel(ctx), timeout)
	go func() {
		defer detachedCtxCancel()
		operationWithErrorHandling(detachedCtx, operationName, operation, mutedErrors...)
	}()
}

func operationWithErrorHandling(ctx context.Context, operationName string, operation func(ctx context.Context) error, mutedErrors ...error) {
	err := operation(ctx)
	if err != nil {
		// spawning off a detached context to make sure we can still report and stat in case the reason for failure is a context deadline exceeded or cancelled
		detached := ctxutil.DetachedCancel(ctx)
		diagnostics.Statter(detached).Counter("backgrounded.error.count", stats.Tags{"operation_name": operationName}, 1)
		if !oneOf(err, mutedErrors...) {
			diagnostics.ReportError(detached, err, "failed backgrounded operation", map[string]string{"gh.authnd.background.operation_name": operationName})
		}
	}
}

func oneOf(err error, mutedErrors ...error) bool {
	for _, muted := range mutedErrors {
		if errors.Is(err, muted) {
			return true
		}
	}
	return false
}
