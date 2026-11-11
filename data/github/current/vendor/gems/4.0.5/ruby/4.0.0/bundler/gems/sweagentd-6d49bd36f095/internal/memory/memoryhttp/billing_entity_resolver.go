package memoryhttp

import (
	"context"

	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/memory/core"
)

// twirpBillingEntityResolver adapts the githubtwirp.ClientInterface to the
// core.BillingEntityResolver interface, keeping the core package decoupled
// from infrastructure concerns.
type twirpBillingEntityResolver struct {
	client githubtwirp.ClientInterface
}

func newTwirpBillingEntityResolver(client githubtwirp.ClientInterface) core.BillingEntityResolver {
	if client == nil {
		return nil
	}
	return &twirpBillingEntityResolver{client: client}
}

func (r *twirpBillingEntityResolver) ResolveBillingEntity(ctx context.Context, userID int64) (core.BillingEntity, error) {
	be, err := githubtwirp.ResolveBillingEntity(ctx, r.client, userID)
	if err != nil {
		return core.BillingEntity{}, err
	}
	return core.BillingEntity{
		OrganizationID: be.OrganizationID,
		EnterpriseID:   be.EnterpriseID,
		Resolved:       be.Resolved,
	}, nil
}
