package resource

import (
	"context"
	"fmt"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/migrations-vnext/internal/pkg/client"
	octov1 "github.com/github/migrations-vnext/internal/pkg/octoshift/imports/v1"
	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
)

type organization struct {
	baseHandler
	adminUserID    int64
	enterpriseID   int64
	pb             *v1.Organization
	importedResult *octov1.ImportOrganizationResponse
}

var _ handler = (*organization)(nil)

func newOrganization(pb *v1.Organization, adminUserID, enterpriseID int64, logger log.Logger) *organization {
	return &organization{
		enterpriseID: enterpriseID,
		baseHandler:  baseHandler{logger},
		pb:           pb,
		adminUserID:  adminUserID,
	}
}

func (o *organization) resourceID() string {
	return o.pb.ResourceId
}

func (o *organization) load(ctx context.Context, importer client.Importer, _ resolvedIDsByResource) error {
	if o.adminUserID == 0 {
		return fmt.Errorf("admin user id is required")
	}

	req := &octov1.ImportOrganizationRequest{
		TargetEnterpriseId: o.enterpriseID,
		TargetOrgName:      o.pb.Name,
		UserId:             o.adminUserID,
	}

	var err error
	o.importedResult, err = importer.ImportOrganization(ctx, req)
	if err != nil {
		o.logger.WithError(err).Error("failed to import organization", kvp.Any("request", req))
		return fmt.Errorf("failed to load organization: %w", err)
	}

	return nil
}

func (o *organization) newResolvedIDs() resolvedIDsByResource {
	return resolvedIDsByResource{
		o.resourceID(): &transformedValues{
			int64Val: o.importedResult.Id,
			strVal:   parameterize(o.pb.Name),
		},
	}
}
