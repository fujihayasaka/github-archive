package usage

import (
	"context"

	"github.com/github/billing-platform/internal/logging"
	"github.com/github/billing-platform/lib/azure/kusto"
	"github.com/github/billing-platform/lib/engines"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/billing-platform/lib/twirp/proto"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
)

type UsageService struct {
	kustoService kusto.KustoService
	usageEngine  *engines.UsageEngine
	logger       log.Logger
	statter      stats.Client
}

func NewUsageService(kustoService kusto.KustoService, usageEngine *engines.UsageEngine, logger log.Logger, statter stats.Client) *UsageService {
	return &UsageService{
		kustoService: kustoService,
		usageEngine:  usageEngine,
		logger:       logger,
		statter:      statter,
	}
}

func (u *UsageService) GetTopUsageGroupings(ctx context.Context, request *models.UsageRequest) ([]int64, error) {
	isOrgAdminRequest := len(request.FilteredOrgs) > 0

	topResourceIDs, err := u.usageEngine.GetTopOrgRepoFromCache(ctx, u.logger, request)
	if err != nil {
		u.logger.WithError(err).Error("Error getting top org / repo from cache", kvp.Any("UsageRequest", request))
	}

	if topResourceIDs == nil {
		if request.GroupBy == proto.UsageGroupBy_GroupByRepository {
			topRepoIDs, err := u.kustoService.GetTopReposByGrossAmount(ctx, request)
			if err != nil {
				u.logger.WithError(err).Error("Failed to get top repos by gross amount from Kusto Service",
					kvp.Any("UsageRequest", request))
				return nil, err
			}

			u.logger.Info(
				"top repositories for customer",
				kvp.Int64s("gh.billing_platform.top_repo_ids", topRepoIDs),
				kvp.Bool("gh.billing_platform.org_admin_request", isOrgAdminRequest),
				kvp.Int64(logging.BillingCustomerId, request.CustomerId),
				kvp.String(logging.BillingPlatformCostCenterUUID, request.CostCenterId),
			)

			topResourceIDs = topRepoIDs
		} else if request.GroupBy == proto.UsageGroupBy_GroupByOrganization {
			topOrgIDs, err := u.kustoService.GetTopOrgsByGrossAmount(ctx, request)
			if err != nil {
				u.logger.WithError(err).Error("Failed to get top orgs by gross amount from Kusto Service",
					kvp.Any("UsageRequest", request))
				return nil, err
			}

			u.logger.Info(
				"top organizations for customer",
				kvp.Int64s("gh.billing_platform.top_org_ids", topOrgIDs),
				kvp.Bool("gh.billing_platform.org_admin_request", isOrgAdminRequest),
				kvp.Int64(logging.BillingCustomerId, request.CustomerId),
				kvp.String(logging.BillingPlatformCostCenterUUID, request.CostCenterId),
			)

			topResourceIDs = topOrgIDs
		}

		// only cache results if this is not an org admin request and top org / repo IDs is not empty
		if !isOrgAdminRequest && len(topResourceIDs) > 0 {
			err := u.usageEngine.UpsertTopOrgRepoResponse(ctx, u.logger, request, topResourceIDs)
			if err != nil {
				u.logger.WithError(err).Error("Failed to upsert top org / repo response")
			}
		}
	} else {
		u.statter.Counter("top_org_repo.cache.hit", nil, 1)
	}

	return topResourceIDs, nil
}
