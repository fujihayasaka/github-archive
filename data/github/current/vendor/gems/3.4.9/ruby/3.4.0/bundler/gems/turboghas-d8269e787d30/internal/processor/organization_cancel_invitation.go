package processor

import (
	"context"

	githubv1 "github.com/github/hydro-schemas-go/hydro/schemas/github/v1"
	"github.com/pkg/errors"
)

var _ = CacheInvalidationTopic("cp1-iad.ingest.github.v1.OrganizationCancelInvitation")

func (p *Processor) organizationCancelInvitation(ctx context.Context, organizationCancelInvitation *githubv1.OrganizationCancelInvitation) error {
	return errors.Wrap(p.syncOrganizationEntity(ctx, organizationCancelInvitation.Organization), "failed to process OrganizationCancelInvitation")
}
