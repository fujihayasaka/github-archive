package processor

import (
	"context"

	enterprisev0 "github.com/github/hydro-schemas-go/hydro/schemas/github/enterprise_account/v0"
	"github.com/pkg/errors"
)

var _ = CacheInvalidationTopic("github.enterprise_account.v0.OrganizationTransfer")

func (p *Processor) organizationTransfer(ctx context.Context, organizationTransfer *enterprisev0.OrganizationTransfer) error {
	return errors.Wrap(p.syncOrganizationEntity(ctx, organizationTransfer.Organization), "failed to process OrganizationTransfer")
}
