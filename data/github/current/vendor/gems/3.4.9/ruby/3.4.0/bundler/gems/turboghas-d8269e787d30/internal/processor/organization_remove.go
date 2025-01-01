package processor

import (
	"context"

	enterprisev0 "github.com/github/hydro-schemas-go/hydro/schemas/github/enterprise_account/v0"
	"github.com/pkg/errors"
)

var _ = CacheInvalidationTopic("github.enterprise_account.v0.OrganizationRemove")

func (p *Processor) organizationRemove(ctx context.Context, organizationRemove *enterprisev0.OrganizationRemove) error {
	return errors.Wrap(p.syncOrganizationEntity(ctx, organizationRemove.Organization), "failed to process OrganizationRemove")
}
