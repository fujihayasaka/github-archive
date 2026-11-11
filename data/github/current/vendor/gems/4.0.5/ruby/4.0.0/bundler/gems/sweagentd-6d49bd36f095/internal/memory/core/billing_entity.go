package core

import (
	"context"
	"errors"
)

// BillingEntity represents the resolved billing entity for a Copilot user,
// identifying which organization and/or enterprise is providing the Copilot license.
type BillingEntity struct {
	OrganizationID uint64
	EnterpriseID   uint64
	// Resolved is true when the upstream service was able to determine a billing entity.
	// It is false for multi-SKU users who haven't selected a default billing entity.
	Resolved bool
}

// IsUnresolved returns true when the billing entity could not be determined.
func (b BillingEntity) IsUnresolved() bool {
	return !b.Resolved
}

// IsZero returns true when both billing IDs are zero, regardless of the Resolved field.
// This can indicate a CfI user or an unresolved billing entity.
func (b BillingEntity) IsZero() bool {
	return b.OrganizationID == 0 && b.EnterpriseID == 0
}

// UserMemoryQuery holds optional query parameters for user memory retrieval.
// The zero value represents an unfiltered query.
type UserMemoryQuery struct {
	// BillingFilter restricts results to memories matching this billing entity.
	// When nil, no billing filtering is applied.
	BillingFilter *BillingEntity
}

// BillingEntityResolver resolves the billing entity for a user's Copilot license.
// Implementations should cache results appropriately (e.g., per-request memoization).
type BillingEntityResolver interface {
	ResolveBillingEntity(ctx context.Context, userID int64) (BillingEntity, error)
}

// Sentinel errors for billing entity resolution.
var (
	// ErrBillingEntityUnresolved indicates the user has multiple SKUs and has not
	// selected a default billing entity. The handler should map this to 422 with
	// a remediation message.
	ErrBillingEntityUnresolved = errors.New("billing entity unresolved: user has not selected a default billing entity")

	// ErrBillingEntityResolutionFailed indicates an infrastructure failure resolving
	// the billing entity. The handler should map this to 500.
	ErrBillingEntityResolutionFailed = errors.New("failed to resolve billing entity")
)
