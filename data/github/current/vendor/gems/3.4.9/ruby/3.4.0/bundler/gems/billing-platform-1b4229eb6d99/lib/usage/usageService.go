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
	"github.com/pkg/errors"
	"golang.org/x/sync/errgroup"
)

type UsageService struct {
	kustoService kusto.KustoService
	usageEngine  engines.UsageEngineInterface
	logger       log.Logger
	statter      stats.Client
}

func NewUsageService(kustoService kusto.KustoService, usageEngine engines.UsageEngineInterface, logger log.Logger, statter stats.Client) *UsageService {
	return &UsageService{
		kustoService: kustoService,
		usageEngine:  usageEngine,
		logger:       logger,
		statter:      statter,
	}
}

func (u *UsageService) GetTopUsageGroupings(ctx context.Context, request *models.UsageRequest) ([]int64, error) {
	isOrgAdminRequest := len(request.FilteredOrgs) > 0
	isFilteringForCostCenterUsage := request.CostCenterId != ""

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
		// also only cache if we are not searching for a specific cost centers usage
		if !isOrgAdminRequest && !isFilteringForCostCenterUsage && len(topResourceIDs) > 0 {
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

func (u *UsageService) BuildEnterpriseUsageTotals(input *proto.GetEnterpriseUsageTotalsRequest, allItems []*models.Item, costCenters []*models.CostCenter) (*proto.GetEnterpriseUsageTotalsResponse, error) {
	usageTotalMap := make(map[string]*proto.EnterpriseUsageTotal)
	billedAmountMap := make(map[string]int64)
	totalGrossAmount := int64(0)

	// build the initial totals map
	for _, costCenter := range costCenters {
		usageTotalMap[costCenter.Id] = &proto.EnterpriseUsageTotal{
			Id:   costCenter.Id,
			Name: costCenter.Name,
		}
	}
	usageTotalMap[input.CustomerId] = &proto.EnterpriseUsageTotal{
		Id:   input.CustomerId,
		Name: "Enterprise Only",
	}

	// accumulate the int64 billed amounts in a map by cost center and enterprise ID
	for _, item := range allItems {
		totalGrossAmount += item.BilledAmount

		// this is a cost center, add the amount to the total for the cost center
		if item.IsCostCenterProxy() {
			costCenterUUID := item.EntityDetail.CostCenterDetail.CostCenterUUID

			if _, ok := billedAmountMap[costCenterUUID]; !ok {
				billedAmountMap[costCenterUUID] = item.BilledAmount
			} else {
				billedAmountMap[costCenterUUID] += item.BilledAmount
			}
		} else {
			if _, ok := billedAmountMap[input.CustomerId]; !ok {
				billedAmountMap[input.CustomerId] = item.BilledAmount
			} else {
				billedAmountMap[input.CustomerId] += item.BilledAmount
			}
		}
	}

	// assign the accumulated amounts to the usage totals map
	for id, total := range usageTotalMap {
		total.GrossAmount = models.ToDecimalAmount(billedAmountMap[id])
	}

	// get slice of usage totals
	usageTotals := make([]*proto.EnterpriseUsageTotal, 0, len(usageTotalMap))
	for _, total := range usageTotalMap {
		usageTotals = append(usageTotals, total)
	}

	return &proto.GetEnterpriseUsageTotalsResponse{
		TotalGrossAmount: models.ToDecimalAmount(totalGrossAmount),
		Totals:           usageTotals,
	}, nil
}

func (u *UsageService) GetTopOrgRepoUsageLineItems(ctx context.Context, input *proto.TopOrgRepoUsageRequest, topUsagePartitionDetails []*models.UsagePartitionDetail, allUsagePartitionDetails []*models.UsagePartitionDetail) (*proto.TopOrgRepoUsageResponse, error) {
	u.logger.Info("Querying GetTopOrgRepoUsageLineItems partition details", kvp.Int("billing.partitionDetailsLength", len(topUsagePartitionDetails)+len(allUsagePartitionDetails)), kvp.Int64(logging.BillingCustomerId, input.CustomerId))

	errs, gctx := errgroup.WithContext(ctx)

	topUsagePartitionDetailUsageItems := make([][]*models.UsageItem, len(topUsagePartitionDetails))
	for i, partitionDetail := range topUsagePartitionDetails {
		errs.Go(func() error {
			if input.IncludeDiscounts {
				items, err := u.usageEngine.GetNetUsageLineItems(gctx, u.logger, partitionDetail)
				if err != nil {
					return err
				}

				topUsagePartitionDetailUsageItems[i] = items.UsageItems
			} else {
				items, err := u.usageEngine.GetUsageLineItems(gctx, u.logger, partitionDetail)
				if err != nil {
					return err
				}

				topUsagePartitionDetailUsageItems[i] = items
			}

			return nil
		})
	}

	allUsagePartitionDetailUsageItems := make([][]*models.UsageItem, len(allUsagePartitionDetails))
	for i, partitionDetail := range allUsagePartitionDetails {
		errs.Go(func() error {
			if input.IncludeDiscounts {
				items, err := u.usageEngine.GetNetUsageLineItems(gctx, u.logger, partitionDetail)
				if err != nil {
					return err
				}

				allUsagePartitionDetailUsageItems[i] = items.UsageItems
			} else {
				items, err := u.usageEngine.GetUsageLineItems(gctx, u.logger, partitionDetail)
				if err != nil {
					return err
				}

				allUsagePartitionDetailUsageItems[i] = items
			}

			return nil
		})
	}

	if err := errs.Wait(); err != nil {
		return nil, errors.Wrap(err, "Failed to query top org / repo usage line items")
	}

	// flatten the nested partition detail usage item slices into a single slice so we can group and run other usage calculations
	var topUsageLineItems []*models.UsageItem
	for _, partitionDetailUsageItems := range topUsagePartitionDetailUsageItems {
		topUsageLineItems = append(topUsageLineItems, partitionDetailUsageItems...)
	}

	var allUsageLineItems []*models.UsageItem
	for _, partitionDetailUsageItems := range allUsagePartitionDetailUsageItems {
		allUsageLineItems = append(allUsageLineItems, partitionDetailUsageItems...)
	}

	groupedTopUsageLineItems := u.usageEngine.GroupLineItems(topUsageLineItems, input.GroupBy, input.BillingPeriod)
	protoTopUsageLineItems := make([]*proto.TopOrgRepoUsage, len(groupedTopUsageLineItems))
	for i, item := range groupedTopUsageLineItems {
		protoTopUsageLineItems[i] = item.ToTopOrgRepoUsage()
	}

	groupedAllUsage := u.usageEngine.GroupLineItems(allUsageLineItems, input.GroupBy, input.BillingPeriod)
	otherUsages := u.usageEngine.CalculateOtherUsages(groupedAllUsage, groupedTopUsageLineItems, input.BillingPeriod)
	protoOtherUsageLineItems := make([]*proto.BillingItem, len(otherUsages))
	for i, item := range otherUsages {
		protoOtherUsageLineItems[i] = item.ToOtherUsage()
	}

	return &proto.TopOrgRepoUsageResponse{
		TopUsages:   protoTopUsageLineItems,
		OtherUsages: protoOtherUsageLineItems,
	}, nil
}
