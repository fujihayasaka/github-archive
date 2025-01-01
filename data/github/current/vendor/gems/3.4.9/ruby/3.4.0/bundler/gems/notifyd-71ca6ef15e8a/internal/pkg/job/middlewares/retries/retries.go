// Package retries implements retries for aqueduct messages.
package retries

import (
	"context"

	"github.com/github/notifyd/internal/pkg/tenancy"
)

// Retrier enqueues a message for redelivery
type Retrier interface {
	Retry(context.Context, tenancy.Tenant, []byte) error
}
