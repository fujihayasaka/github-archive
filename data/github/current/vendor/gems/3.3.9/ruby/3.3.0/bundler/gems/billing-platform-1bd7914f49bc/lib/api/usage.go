// This handles calling item mappers and passing the results to the db and getting them back
package api

import (
	"context"
	"fmt"
	"sync"

	"github.com/github/billing-platform/internal/logging"
	"github.com/github/billing-platform/internal/nano"
	"github.com/github/billing-platform/lib/azure/kusto"
	"github.com/github/billing-platform/lib/config"
	"github.com/github/billing-platform/lib/engines"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/billing-platform/lib/twirp/proto"
	"github.com/github/billing-platform/lib/usage"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"

	"github.com/github/github-telemetry-go/log"
	"github.com/pkg/errors"
	"golang.org/x/sync/errgroup"
)

type UsageApi struct {
	invoiceEngine    *engines.InvoiceEngine
	usageEngine      *engines.UsageEngine
	pricingEngine    *engines.PricingEngine
	customerEngine   *engines.CustomerEngine
	costCenterEngine engines.CostCenterEngineInterface
	logger           log.Logger
	statter          stats.Client
	kustoService     kusto.KustoService
	usageService     *usage.UsageService
}

func NewUsageAPI(invoiceEngine *engines.InvoiceEngine, usageEngine *engines.UsageEngine, pricingEngine *engines.PricingEngine, customerEngine *engines.CustomerEngine, costCenterEngine engines.CostCenterEngineInterface, logger log.Logger, statter stats.Client, kustoService kusto.KustoService, usageService *usage.UsageService) *UsageApi {
	return &UsageApi{
		invoiceEngine:    invoiceEngine,
		usageEngine:      usageEngine,
		pricingEngine:    pricingEngine,
		customerEngine:   customerEngine,
		costCenterEngine: costCenterEngine,
		logger:           logger.Named("UsageApi"),
		statter:          statter,
		kustoService:     kustoService,
		usageService:     usageService,
	}
}

func (api *UsageApi) GetTopOrgRepoUsageLineItems(ctx context.Context, input *proto.TopOrgRepoUsageRequest) (*proto.TopOrgRepoUsageResponse, error) {
	if input.GroupBy != proto.UsageGroupBy_GroupByRepository && input.GroupBy != proto.UsageGroupBy_GroupByOrganization {
		return nil, fmt.Errorf("GroupBy must be either GroupByRepository or GroupByOrganization")
	}

	isOrgAdminRequest := len(input.OrganizationIds) > 0

	request := api.FromTopOrgRepoProtoToUsageRequest(input)
	topResourceIDs, err := api.usageService.GetTopUsageGroupings(ctx, request)
	if err != nil {
		return nil, err
	}

	// Get usage data
	errs, gctx := errgroup.WithContext(ctx)

	var topUsageMutex = &sync.Mutex{}
	var topUsageLineItems []*models.Item
	var allUsageMutex = &sync.Mutex{}
	var allUsage []*models.Item

	switch input.CostCenterId {
	case "All":
		// Aggregate Usage behavior
		costCenters, bpErr := api.getAllCostCentersForCustomer(ctx, fmt.Sprintf("%d", input.CustomerId))
		if bpErr != nil {
			api.logger.WithError(bpErr).Error("Failed to get all cost centers for customer")
			return nil, bpErr
		}

		for _, resourceID := range topResourceIDs {
			// Get usage of the repo/org from each costcenter - this resource could have moved between cost centers,
			// so we check the existance of a usage partition with the repo/org in each cost center
			for _, costCenter := range costCenters {
				errs.Go(func() error {
					partitionDetail, err := FromTopOrgRepoUsageRequestToUsagePartitionDetail(resourceID, input, costCenter.Id)
					api.logger.Info("Top org/repo usage partition detail", kvp.Any("partitionDetail", partitionDetail))
					if err != nil {
						return err
					}

					items, err := api.usageEngine.GetLineItems(gctx, api.logger, partitionDetail)
					if err != nil {
						return err
					}

					api.logger.Info("Top org/repo usage line items count", kvp.Int("lineItems count", len(items)))
					if items != nil {
						// append to shared slice is not thread safe so we need to lock
						topUsageMutex.Lock()
						topUsageLineItems = append(topUsageLineItems, items...)
						topUsageMutex.Unlock()
					}
					return nil
				})
			}

			// Get usage of the top repo/org from parent enterprise
			errs.Go(func() error {
				partitionDetail, err := FromTopOrgRepoUsageRequestToUsagePartitionDetail(resourceID, input, fmt.Sprintf("%d", input.CustomerId))
				api.logger.Info("Top org/repo usage partition detail", kvp.Any("partitionDetail", partitionDetail))
				if err != nil {
					return err
				}

				items, err := api.usageEngine.GetLineItems(gctx, api.logger, partitionDetail)
				if err != nil {
					return err
				}

				api.logger.Info("Top org/repo usage line items count", kvp.Int("lineItems count", len(items)))
				if items != nil {
					// append to shared slice is not thread safe so we need to lock
					topUsageMutex.Lock()
					topUsageLineItems = append(topUsageLineItems, items...)
					topUsageMutex.Unlock()
				}
				return nil
			})
		}
		api.logger.Info("GetTopOrgRepoUsageLineItems", kvp.Int64("gh.billing_platform.top_usage_count", int64(len(topUsageLineItems))))

		// Other Usage
		// only query all usage if len of top resources is the same as our limit as there will be no need
		// to calculate the "other" usage if there are fewer than our limits resources

		if len(topResourceIDs) == int(input.Limit) {
			// Get all usage from all cost centers
			for _, costCenter := range costCenters {
				errs.Go(func() error {
					partitionDetail, err := FromTopOrgRepoUsageRequestToUsagePartitionDetailForOthers(input, costCenter.Id)
					if err != nil {
						return err
					}

					items, err := api.usageEngine.GetLineItems(gctx, api.logger, partitionDetail)
					if err != nil {
						return err
					}
					if items != nil {
						allUsageMutex.Lock()
						allUsage = append(allUsage, items...)
						allUsageMutex.Unlock()
					}

					return nil
				})
			}
			// Get all usage from parent enterprise
			errs.Go(func() error {
				partitionDetail, err := FromTopOrgRepoUsageRequestToUsagePartitionDetailForOthers(input, fmt.Sprintf("%d", input.CustomerId))
				if err != nil {
					return err
				}

				items, err := api.usageEngine.GetLineItems(gctx, api.logger, partitionDetail)
				if err != nil {
					return err
				}
				if items != nil {
					allUsageMutex.Lock()
					allUsage = append(allUsage, items...)
					allUsageMutex.Unlock()
				}

				return nil
			})

		}

	default:
		// current behavior - input.costCenterId contains the customer id if enterprise only usage else it contains the cost center Id and a specific cost center's  usage is requested
		var entityId string
		if input.CostCenterId != "" && input.CostCenterId != fmt.Sprintf("%d", input.CustomerId) {
			entityId = input.CostCenterId
		} else {
			entityId = fmt.Sprintf("%d", input.CustomerId)
		}

		for _, resourceID := range topResourceIDs {
			errs.Go(func() error {
				partitionDetail, err := FromTopOrgRepoUsageRequestToUsagePartitionDetail(resourceID, input, entityId)
				api.logger.Info("Top org/repo usage partition detail", kvp.Any("partitionDetail", partitionDetail))
				if err != nil {
					return err
				}

				items, err := api.usageEngine.GetLineItems(gctx, api.logger, partitionDetail)
				if err != nil {
					return err
				}

				api.logger.Info("Top org/repo usage line items count", kvp.Int("lineItems count", len(items)))
				if items != nil {
					// append to shared slice is not thread safe so we need to lock
					topUsageMutex.Lock()
					topUsageLineItems = append(topUsageLineItems, items...)
					topUsageMutex.Unlock()
				}
				return nil
			})
		}
		api.logger.Info("GetTopOrgRepoUsageLineItems", kvp.Int64("gh.billing_platform.top_usage_count", int64(len(topUsageLineItems))))
		// only query all usage if len of top resources is the same as our limit as there will be no need
		// to calculate the "other" usage if there are fewer than our limits resources
		if len(topResourceIDs) == int(input.Limit) {
			errs.Go(func() error {
				partitionDetail, err := FromTopOrgRepoUsageRequestToUsagePartitionDetailForOthers(input, entityId)
				if err != nil {
					return err
				}

				items, err := api.usageEngine.GetLineItems(gctx, api.logger, partitionDetail)
				if err != nil {
					return err
				}

				allUsage = items

				return nil
			})
		}

	}

	if err := errs.Wait(); err != nil {
		return nil, errors.Wrap(err, "Failed to query top org / repo usage line items")
	}

	groupedTopUsageLineItems := api.usageEngine.GroupLineItems(topUsageLineItems, input.GroupBy, input.BillingPeriod)
	protoTopUsageLineItems := make([]*proto.TopOrgRepoUsage, len(groupedTopUsageLineItems))
	for i, item := range groupedTopUsageLineItems {
		protoTopUsageLineItems[i] = item.ToTopOrgRepoUsage()
	}

	groupedAllUsage := api.usageEngine.GroupLineItems(allUsage, input.GroupBy, input.BillingPeriod)
	otherUsages := api.usageEngine.CalculateOtherUsages(groupedAllUsage, groupedTopUsageLineItems, input.BillingPeriod)
	protoOtherUsageLineItems := make([]*proto.BillingItem, len(otherUsages))
	for i, item := range otherUsages {
		protoOtherUsageLineItems[i] = item.ToOtherUsage()
	}

	topUsageAmount := float64(0)
	for _, item := range protoTopUsageLineItems {
		topUsageAmount += item.BilledAmount
	}

	otherUsageAmount := float64(0)
	for _, item := range protoOtherUsageLineItems {
		otherUsageAmount += item.BilledAmount
	}

	api.logger.Info(
		"GetTopOrgRepoUsageLineItems summary",
		kvp.Float64("gh.billing_platform.top_usage_amount", topUsageAmount),
		kvp.Float64("gh.billing_platform.other_usage_amount", otherUsageAmount),
		kvp.Bool("gh.billing_platform.org_admin_request", isOrgAdminRequest),
		kvp.Int64(logging.BillingCustomerId, input.CustomerId),
		kvp.String(logging.BillingPlatformCostCenterUUID, input.CostCenterId),
	)
	api.statter.Counter("usage_filter.billing_period", stats.Tags{"period": input.BillingPeriod.String()}, 1)

	return &proto.TopOrgRepoUsageResponse{
		TopUsages:   protoTopUsageLineItems,
		OtherUsages: protoOtherUsageLineItems,
	}, nil
}

func (api *UsageApi) GetWatermarkLevel(ctx context.Context, input *proto.GetWatermarkLevelRequest) (*proto.GetWatermarkLevelResponse, error) {
	if input.UsageEntityId == "" {
		return nil, fmt.Errorf("usageEntityId is required")
	}

	if input.Sku == "" {
		return nil, fmt.Errorf("SKU is required")
	}

	pk := fmt.Sprintf("%s:%s:events:rollups", input.UsageEntityId, input.Sku)
	levelItem, err := api.usageEngine.GetWatermarkEventRollupsTotal(ctx, api.logger, pk, input.OrgId, input.RepoId)
	if err != nil {
		return &proto.GetWatermarkLevelResponse{}, err
	}

	if levelItem == nil {
		return &proto.GetWatermarkLevelResponse{
			Sku:      input.Sku,
			Quantity: 0,
		}, nil
	}

	nanoQuantity := nano.NewFromInt(levelItem.Quantity)
	nanoQuantity = nanoQuantity.Div(nano.NewFromInt(models.ToWholeAmount[int64](24)))

	return &proto.GetWatermarkLevelResponse{
		Sku:      input.Sku,
		Quantity: models.ToDecimalAmount[int64](nanoQuantity.Int64()),
	}, nil
}

// GetInvoice implements proto.UsageApi
func (api *UsageApi) GetInvoice(ctx context.Context, input *proto.GetInvoiceRequest) (*proto.GetInvoiceResponse, error) {
	ipd := &models.InvoicePartitionDetail{
		CustomerId: input.CustomerId,
		Year:       input.Year,
		Month:      input.Month,
	}
	invoice, err := api.invoiceEngine.GetInvoice(ctx, api.logger, models.NewInvoiceKey(ipd))

	if err != nil {
		return nil, err
	}

	if invoice == nil {
		return &proto.GetInvoiceResponse{
			Invoice: nil,
		}, nil
	}

	return &proto.GetInvoiceResponse{
		Invoice: invoice.ToProto(),
	}, nil
}

// GetDiscountLineItems implements proto.UsageApi
func (api *UsageApi) GetDiscountLineItems(ctx context.Context, input *proto.GetUsageRequest) (*proto.GetDiscountLineItemsResponse, error) {
	var partitionDetail *models.UsagePartitionDetail
	var err error
	partitionDetail, err = FromUsageRequestToUsagePartitionDetail(input)
	if err != nil {
		return nil, err
	}

	items, err := api.usageEngine.GetDiscountLineItems(ctx, api.logger, partitionDetail)

	if err != nil {
		return nil, err
	}

	protoItems := make([]*proto.DiscountItem, len(items))
	for i, item := range items {
		item.Pricing.UnitType = api.pricingEngine.GetUnitTypeForSku(item.GetSku())
		protoItems[i] = item.ToProto()
	}

	return &proto.GetDiscountLineItemsResponse{
		DiscountItems: protoItems,
	}, nil
}

// GetUsageLineItems implements proto.UsageApi
func (api *UsageApi) GetUsageLineItems(ctx context.Context, input *proto.GetUsageRequest) (*proto.GetUsageLineItemsResponse, error) {
	var partitionDetail *models.UsagePartitionDetail
	var err error
	partitionDetail, err = FromUsageRequestToUsagePartitionDetail(input)
	if err != nil {
		return nil, err
	}

	items, err := api.usageEngine.GetLineItems(ctx, api.logger, partitionDetail)

	if err != nil {
		return nil, err
	}

	protoItems := make([]*proto.BillingItem, len(items))
	for i, item := range items {
		item.Pricing.UnitType = api.pricingEngine.GetUnitTypeForSku(item.GetSku())
		protoItems[i] = item.ToProto()
	}

	return &proto.GetUsageLineItemsResponse{
		BillingItems: protoItems,
	}, nil
}

// GetNetUsageLineItems implements proto.UsageApi
func (api *UsageApi) GetNetUsageLineItems(ctx context.Context, input *proto.GetUsageRequest) (*proto.GetNetUsageLineItemsResponse, error) {
	ctx = config.CreateContextWithApiMetricName(ctx, config.NetUsageKey)
	// Get all cost centers and the partition details for each cost center
	var costCenters []*models.CostCenter
	var bpErr error
	if input.CostCenterId == "All" {
		costCenters, bpErr = api.getAllCostCentersForCustomer(ctx, input.UsageEntityId)
		if bpErr != nil {
			api.logger.WithError(bpErr).Error("Failed to get all cost centers for customer")
			return nil, bpErr
		}
	}

	partitionDetails, err := FromUsageRequestToUsagePartitionDetails(input, costCenters)
	if err != nil {
		api.logger.WithError(err).Error("Failed to get partition details")
		return nil, err
	}

	mutex := &sync.Mutex{}
	errs, gctx := errgroup.WithContext(ctx)
	protoNetUsageItems := make([]*proto.NetUsageItem, 0)
	for _, partitionDetail := range partitionDetails {
		errs.Go(func() error {
			items, err := api.usageEngine.GetProtoNetUsageLineItems(gctx, api.logger, partitionDetail, costCenters)
			if err != nil {
				api.logger.WithError(err).Error("Failed to get net usage line items")
				return err
			}

			mutex.Lock()
			protoNetUsageItems = append(protoNetUsageItems, items...)
			mutex.Unlock()

			return nil
		})
	}

	if err := errs.Wait(); err != nil {
		api.logger.WithError(err).Error("Failed to query usage")
		return nil, errors.Wrap(err, "Failed to query usage")
	}

	ruValue := config.GetApiLevelRequestUsage(ctx, config.NetUsageKey)
	api.logger.Info("GetNetUsageLineItems RU count", kvp.Any("ruValue", ruValue))
	api.statter.Distribution("usageApiGetNetUsageLineItemsTotalRUCount", stats.Tags{}, float64(ruValue))
	api.statter.Counter("usage_filter.billing_period", stats.Tags{"period": input.BillingPeriod.String()}, 1)

	return &proto.GetNetUsageLineItemsResponse{
		NetUsageItems: protoNetUsageItems,
	}, nil
}

// GetUsageData implements proto.UsageApi
func (api *UsageApi) GetUsageChartData(ctx context.Context, input *proto.GetUsageChartDataRequest) (*proto.GetUsageChartDataResponse, error) {
	ctx = config.CreateContextWithApiMetricName(ctx, config.GetUsageChartDataKey)
	// Get all cost centers and the partition details for each cost center
	var costCenters []*models.CostCenter
	var bpErr error
	costCenters, bpErr = api.getAllCostCentersForCustomer(ctx, input.UsageEntityId)
	if bpErr != nil && bpErr.Error() == "customer not found" {
		// If the customer is not found, we should return an empty response
		// It may just be that they have no usage data, not that they don't exist
		usageChartData := make([]*proto.UsageChartDataset, 0)
		return &proto.GetUsageChartDataResponse{
			UsageChartData: usageChartData,
		}, nil
	} else if bpErr != nil {
		api.logger.WithError(bpErr).Error("Failed to get all cost centers for customer")
		return nil, bpErr
	}

	partitionDetails, err := FromUsageChartRequestToUsagePartitionDetails(input, costCenters)
	if err != nil {
		return nil, err
	}

	topResourceIDs := make([]int64, 0)
	if input.GroupBy == proto.UsageGroupBy_GroupByRepository || input.GroupBy == proto.UsageGroupBy_GroupByOrganization {
		request, err := api.FromUsageChartDataProtoToUsageRequest(input, 5, api.logger)
		if err != nil {
			return nil, err
		}

		topResourceIDs, err = api.usageService.GetTopUsageGroupings(ctx, request)
		if err != nil {
			// Continue on error as we can still return the usage chart data without the top groupings
			api.logger.WithError(err).Error("Failed to get top usage groupings, continuing")
		}
	}

	errs, gctx := errgroup.WithContext(ctx)
	partitionDetailsUsageItems := make([]engines.PartitionDetailUsageItemResults, len(partitionDetails))
	for i, partitionDetail := range partitionDetails {
		errs.Go(func() error {
			partitionDetailNetUsageItem, err := api.usageEngine.GetNetUsageLineItems(gctx, api.logger, partitionDetail)
			if err != nil {
				return err
			}

			partitionDetailsUsageItems[i] = partitionDetailNetUsageItem
			return nil
		})
	}

	if err := errs.Wait(); err != nil {
		return nil, errors.Wrap(err, "Failed to query usage for usage chart")
	}

	usageChartData := api.usageService.BuildUsageChartData(ctx, api.logger, input, partitionDetailsUsageItems, costCenters, topResourceIDs)

	ruValue := config.GetApiLevelRequestUsage(ctx, config.GetUsageChartDataKey)
	api.logger.Info("GetUsageChartData RU count", kvp.Any("ruValue", ruValue))
	api.statter.Distribution("usageApiGetUsageChartDataRUCount", stats.Tags{}, float64(ruValue))
	api.statter.Counter("usage_filter.billing_period", stats.Tags{"period": input.BillingPeriod.String()}, 1)

	return &proto.GetUsageChartDataResponse{
		UsageChartData: usageChartData,
	}, nil
}

// GetPaginatedUsageLineItems implements proto.UsageApi
func (api *UsageApi) GetPaginatedUsageLineItems(ctx context.Context, input *proto.GetPaginatedUsageRequest) (*proto.GetPaginatedUsageLineItemsResponse, error) {
	// Get all cost centers and the partition details for each cost center
	var costCenters []*models.CostCenter
	var bpErr error

	if input.CostCenterId == "All" {
		costCenters, bpErr = api.getAllCostCentersForCustomer(ctx, input.UsageEntityId)
		if bpErr != nil {
			api.logger.WithError(bpErr).Error("Failed to get all cost centers for customer")
			return nil, bpErr
		}
	}

	partitionDetails, err := FromPaginatedUsageRequestToUsagePartitionDetail(input, costCenters)
	if err != nil {
		api.logger.WithError(err).Error("Failed to get partition details")
		return nil, err
	}

	g, gctx := errgroup.WithContext(ctx)

	var items []*models.OrgRepoItem
	var totalLineItemsCount int64

	cfg, err := config.Load()
	if err != nil {
		log.WithError(err).Fatal("failed to load config")
	}

	if cfg.IsProduction() {
		g.Go(func() error {
			var err error
			totalLineItemsCount, err = api.kustoService.GetDistinctOrgOrRepoTotalCount(gctx, input)
			return err
		})
	}

	var mutex = &sync.Mutex{}
	for _, partitionDetail := range partitionDetails {
		g.Go(func() error {
			var err error
			newItems, err := api.usageEngine.GetPaginatedLineItems(gctx, api.logger, partitionDetail, input)
			if err != nil {
				api.logger.WithError(err).Error("Failed to get paginated line items")
				return err
			}

			// append to shared slice is not thread safe so we need to lock
			mutex.Lock()
			items = append(items, newItems...)
			mutex.Unlock()

			return nil
		})
	}

	if err := g.Wait(); err != nil {
		api.logger.WithError(err).Error("Failed to get paginated line items")
		return nil, fmt.Errorf("error waiting for goroutines fetching distinct org or repo total count and paginated usage line items to finish: %w", err)
	}

	paginatedItems := make([]*proto.OrgRepoItem, len(items))
	for i, item := range items {
		paginatedItems[i] = item.ToProto()
	}

	api.statter.Counter("usage_filter.billing_period", stats.Tags{"period": input.BillingPeriod.String()}, 1)

	return &proto.GetPaginatedUsageLineItemsResponse{
		OrgRepoItems:        paginatedItems,
		TotalLineItemsCount: totalLineItemsCount,
	}, nil
}

// Exposes the events for a given user
func (api *UsageApi) GetUsageEventItems(ctx context.Context, input *proto.GetUsageRequest) (*proto.GetUsageLineItemsResponse, error) {
	partitionDetail, err := FromUsageRequestToUsagePartitionDetail(input)
	if err != nil {
		return nil, err
	}

	items, err := api.usageEngine.GetEventItems(ctx, api.logger, partitionDetail)

	if err != nil {
		return nil, err
	}

	protoItems := make([]*proto.BillingItem, len(items))
	for i, item := range items {
		item.Pricing.UnitType = api.pricingEngine.GetUnitTypeForSku(item.GetSku())
		protoItems[i] = item.ToProto()
	}

	return &proto.GetUsageLineItemsResponse{
		BillingItems: protoItems,
	}, nil
}

// GetRepoUsage implements proto.UsageApi
func (api *UsageApi) GetRepoUsage(ctx context.Context, input *proto.GetRepoUsageRequest) (*proto.GetRepoUsageResponse, error) {
	partitionDetail, err := FromRepoUsageRequestToUsagePartitionDetail(input)
	if err != nil {
		return nil, err
	}

	items, err := api.usageEngine.GetRepoUsage(ctx, api.logger, partitionDetail)
	if err != nil {
		return nil, err
	}

	protoItems := make([]*proto.RepoUsage, len(items))
	for i, item := range items {
		protoItems[i] = item.ToRepoUsageProto()
	}

	return &proto.GetRepoUsageResponse{
		RepoUsages: protoItems,
	}, nil
}

func (api *UsageApi) GetDiscountTotal(ctx context.Context, input *proto.GetUsageRequest) (*proto.GetDiscountTotalResponse, error) {
	partitionDetail, err := FromUsageRequestToUsagePartitionDetail(input)

	if err != nil {
		return nil, err
	}

	usage, hitCache, err := api.usageEngine.GetDiscountTotal(ctx, api.logger, partitionDetail)
	if err != nil {
		return nil, err
	}

	quantity := 0.0
	discountAmount := 0.0
	if usage != nil {
		amount := usage.ToDecimal()
		quantity = amount.Quantity
		discountAmount = amount.DiscountAmount
	}

	unitType := api.pricingEngine.GetUnitTypeForSku(partitionDetail.Sku)

	return &proto.GetDiscountTotalResponse{
		Sku:            partitionDetail.Sku,
		Quantity:       quantity,
		DiscountAmount: discountAmount,
		HitCache:       hitCache,
		UnitType:       unitType.ToProto(),
	}, nil
}

func (api *UsageApi) GetUsageTotal(ctx context.Context, input *proto.GetUsageRequest) (*proto.GetUsageResponse, error) {
	partitionDetail, err := FromUsageRequestToUsagePartitionDetail(input)
	if err != nil {
		return nil, err
	}

	usage, hitCache, err := api.usageEngine.GetUsageTotal(ctx, api.logger, partitionDetail, input.IncludeQuantityGetUsageTotal)
	if err != nil {
		return nil, err
	}

	billableAmount := 0.0
	quantity := 0.0

	if usage != nil {
		amount := usage.ToDecimal()
		billableAmount = amount.BilledAmount

		// Quantity will only be part of the totals calculation if input.IncludeQuantity is true
		// right now, this is only used for integration tests that need to verify the quantity
		quantity = amount.Quantity
	}

	unitType := api.pricingEngine.GetUnitTypeForSku(partitionDetail.Sku)

	return &proto.GetUsageResponse{
		Sku:            partitionDetail.Sku,
		BillableAmount: billableAmount,
		Quantity:       quantity,
		HitCache:       hitCache,
		UnitType:       unitType.ToProto(),
	}, nil
}

func (api *UsageApi) getAllCostCentersForCustomer(ctx context.Context, customerId string) ([]*models.CostCenter, error) {
	customer, err := api.customerEngine.Get(ctx, api.logger, customerId)
	if err != nil {
		return nil, err
	}
	if customer == nil {
		api.logger.Error("Customer not found when looking up all cost centers for customer")
		return nil, errors.New("customer not found")
	}

	costCenters, bpErr := api.costCenterEngine.GetAllCostCenters(ctx, api.logger, customer)
	if bpErr != nil {
		api.logger.WithError(bpErr.OriginalError).Error(bpErr.FriendlyError.Error())
		return nil, bpErr.OriginalError
	}

	return costCenters, nil
}
