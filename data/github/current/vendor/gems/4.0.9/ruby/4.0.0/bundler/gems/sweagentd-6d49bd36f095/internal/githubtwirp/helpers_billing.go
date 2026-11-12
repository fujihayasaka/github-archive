package githubtwirp

import (
	"context"

	"github.com/github/sweagentd/internal/goerrors"
)

// BillingEntity represents the resolved billing entity for a Copilot user,
// identifying which organization and/or enterprise is providing the Copilot license.
type BillingEntity struct {
	OrganizationID uint64
	EnterpriseID   uint64
	// Resolved is true when the monolith was able to determine a billing entity.
	// It is false for multi-SKU users who haven't selected a default billing entity
	Resolved bool
}

// IsUnresolved returns true when the billing entity could not be determined.
// This happens for multi-SKU users who haven't selected a billing entity yet.
func (b BillingEntity) IsUnresolved() bool {
	return !b.Resolved
}

// ResolveBillingEntity returns the billing entity that owns a user's Copilot license.
// It calls GetCopilotUserDetails, which memoizes results in the request context,
// so repeated calls within the same request (e.g. authorization then billing
// resolution) do not trigger additional Twirp RPCs or cache lookups.
//
// The returned IDs vary by plan:
//   - CfI:                  OrganizationID=0, EnterpriseID=0
//   - CfB standalone org:   OrganizationID=N, EnterpriseID=0
//   - CfB under enterprise: OrganizationID=N, EnterpriseID=M
//   - CfE (direct seat):    OrganizationID=0, EnterpriseID=M
func ResolveBillingEntity(ctx context.Context, twirpClient ClientInterface, userID int64) (*BillingEntity, error) {
	userDetails, err := twirpClient.GetCopilotUserDetails(ctx, userID)
	if err != nil {
		return nil, goerrors.Errorf("failed to get user details: %w", err)
	}

	if userDetails == nil {
		return nil, goerrors.Errorf("user details are nil for user %d", userID)
	}

	return &BillingEntity{
		OrganizationID: userDetails.GetBillingOrganizationId(),
		EnterpriseID:   userDetails.GetBillingEnterpriseId(),
		Resolved:       userDetails.GetBillingEntityResolved(),
	}, nil
}
