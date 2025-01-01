package processor

import (
	"context"

	githubv1 "github.com/github/hydro-schemas-go/hydro/schemas/github/v1"
	"github.com/pkg/errors"
)

var _ = CacheInvalidationTopic("cp1-iad.ingest.github.v1.OrganizationInviteMember")

func (p *Processor) organizationInviteMember(ctx context.Context, organizationInviteMember *githubv1.OrganizationInviteMember) error {
	return errors.Wrap(p.syncOrganizationEntity(ctx, organizationInviteMember.Organization), "failed to process OrganizationInviteMember")
}
