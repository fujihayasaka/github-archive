package processor

import (
	"context"

	enterprisev0 "github.com/github/hydro-schemas-go/hydro/schemas/github/enterprise_account/v0"
	"github.com/pkg/errors"
)

var _ = CacheInvalidationTopic("github.enterprise_account.v0.OrganizationUpgrade")

func (p *Processor) organizationUpgrade(ctx context.Context, organizationUpgrade *enterprisev0.OrganizationUpgrade) error {
	return errors.Wrap(p.syncOrganizationEntity(ctx, organizationUpgrade.Organization), "failed to process OrganizationUpgrade")
}
