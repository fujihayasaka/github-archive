// This handles calling item mappers and passing the results to the db and getting them back
package api

import (
	"context"
	"fmt"
	"sync"

	"github.com/github/billing-platform/internal/featureflags"
	"github.com/github/billing-platform/internal/logging"
	"github.com/github/billing-platform/internal/nano"
	"github.com/github/billing-platform/lib/azure/kusto"
	"github.com/github/billing-platform/lib/config"
	"github.com/github/billing-platform/lib/engines"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/billing-platform/lib/twirp/proto"
	"github.com/github/billing-platform/lib/usage"
	"github.com/github/feature-management-client-go/vexi"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	"go.opentelemetry.io/otel/trace"

	"github.com/github/github-telemetry-go/log"
	"github.com/pkg/errors"
	"golang.org/x/sync/errgroup"
)

type UsageApi struct {
	invoiceEngine    *engines.InvoiceEngine
	usageEngine      engines.UsageEngineInterface
	pricingEngine    engines.PricingEngineInterface
	customerEngine   engines.CustomerEngineInterface
	costCenterEngine engines.CostCenterEngineInterface
	discountEngine   engines.DiscountEngineInterface
	logger           log.Logger
	statter          stats.Client
	kustoService     kusto.KustoService
	usageService     *usage.UsageService
	tracer           trace.Tracer
	flagger          *vexi.Client
}

func NewUsageAPI(invoiceEngine *engines.InvoiceEngine, usageEngine engines.UsageEngineInterface, pricingEngine engines.PricingEngineInterface, customerEngine engines.CustomerEngineInterface, costCenterEngine engines.CostCenterEngineInterface, discountEngine engines.DiscountEngineInterface, logger log.Logger, statter stats.Client, kustoService kusto.KustoService, usageService *usage.UsageService, tracer trace.Tracer, flagger *vexi.Client) *UsageApi {
	return &UsageApi{
		invoiceEngine:    invoiceEngine,
		usageEngine:      usageEngine,
		pricingEngine:    pricingEngine,
		customerEngine:   customerEngine,
		costCenterEngine: costCenterEngine,
		discountEngine:   discountEngine,
		logger:           logger.Named("UsageApi"),
		statter:          statter,
		kustoService:     kustoService,
		usageService:     usageService,
		tracer:           tracer,
		flagger:          flagger,
	}
}

func (api *UsageApi) GetTopOrgRepoUsageLineItems(ctx context.Context, input *proto.TopOrgRepoUsageRequest) (*proto.TopOrgRepoUsageResponse, error) {
	if input.GroupBy != proto.UsageGroupBy_GroupByRepository && input.GroupBy != proto.UsageGroupBy_GroupByOrganization {
		return nil, fmt.Errorf("GroupBy must be either GroupByRepository or GroupByOrganization")
	}

	errs, gctx := errgroup.WithContext(ctx)

	var topResourceIDs []int64
	errs.Go(func() error {
		localTopResourceIDs, err := api.usageService.GetTopUsageGroupings(gctx, api.FromTopOrgRepoProtoToUsageRequest(input))
		if err != nil {
			return err
		}

		topResourceIDs = localTopResourceIDs

		return nil
	})

	var costCenters []*models.CostCenter
	errs.Go(func() error {
		localCostCenters, err := api.getAllCostCentersForCustomer(gctx, fmt.Sprintf("%d", input.CustomerId))
		if err != nil {
			return err
		}

		costCenters = localCostCenters

		return nil
	})

	if err := errs.Wait(); err != nil {
		return nil, errors.Wrap(err, "Failed to query top resource IDs and cost centers")
	}

	topUsagePartitionDetails, allUsagePartitionDetails, err := BuildPartitionDetailsForTopOrgRepoUsageRequest(input, costCenters, topResourceIDs)
	if err != nil {
		return nil, err
	}

	topOrgRepoUsageItems, err := api.usageService.GetTopOrgRepoUsageLineItems(ctx, input, topUsagePartitionDetails, allUsagePartitionDetails)
	if err != nil {
		return nil, err
	}

	api.logger.Info(
		"GetTopOrgRepoUsageLineItems summary",
		kvp.Bool("gh.billing_platform.org_admin_request", len(input.OrganizationIds) > 0),
		kvp.Int64(logging.BillingCustomerId, input.CustomerId),
		kvp.String(logging.BillingPlatformCostCenterUUID, input.CostCenterId),
	)
	api.statter.Counter("usage_filter.billing_period", stats.Tags{"period": input.BillingPeriod.String()}, 1)

	return topOrgRepoUsageItems, nil
}

func (api *UsageApi) GetWatermarkLevel(ctx context.Context, input *proto.GetWatermarkLevelRequest) (*proto.GetWatermarkLevelResponse, error) {
	if input.UsageEntityId == "" {
		return nil, fmt.Errorf("usageEntityId is required")
	}

	if input.Sku == "" {
		return nil, fmt.Errorf("SKU is required")
	}

	if input.OrgId == 0 {
		api.logger.Info("GetWatermarkLevel blank OrgId", kvp.String("customerId", input.UsageEntityId), kvp.String("sku", input.Sku), kvp.Int64("repoId", input.RepoId))
		api.statter.Counter("get_watermark_level.blank_org_id", stats.Tags{}, 1)
	}

	var nanoQuantity *nano.Nano
	total, err := api.usageEngine.GetWatermarkEventRollupsTotal(ctx, api.logger, input.UsageEntityId, input.Sku, input.OrgId, input.RepoId)
	if err != nil {
		return &proto.GetWatermarkLevelResponse{}, err
	}

	nanoQuantity = nano.NewFromInt(total)

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
		skipCache := false
		item.Pricing.UnitType, err = api.pricingEngine.GetUnitTypeForSku(ctx, api.logger, item.GetSku(), "GetDiscountLineItems", skipCache)
		if err != nil {
			return nil, err
		}

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
		skipCache := false
		item.Pricing.UnitType, err = api.pricingEngine.GetUnitTypeForSku(ctx, api.logger, item.GetSku(), "GetUsageLineItems", skipCache)
		if err != nil {
			return nil, err
		}

		protoItems[i] = item.ToProto()
	}

	return &proto.GetUsageLineItemsResponse{
		BillingItems: protoItems,
	}, nil
}

// GetNetUsageLineItems implements proto.UsageApi
func (api *UsageApi) GetNetUsageLineItems(ctx context.Context, input *proto.GetUsageRequest) (*proto.GetNetUsageLineItemsResponse, error) {
	ctx, sp := api.tracer.Start(ctx, "UsageApi.GetNetUsageLineItems")
	defer sp.End()

	ctx = config.CreateContextWithApiMetricName(ctx, config.NetUsageKey)

	customerId := input.UsageEntityId
	// Get all cost centers and the partition details for each cost center
	var costCenters []*models.CostCenter
	var bpErr error
	if input.CostCenterId == "" {
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

	api.logger.Info("Querying GetNetUsageLineItems partition details", kvp.Int("billing.partitionDetailsLength", len(partitionDetails)), kvp.String(logging.BillingCustomerId, input.UsageEntityId))

	mutex := &sync.Mutex{}
	errs, gctx := errgroup.WithContext(ctx)
	protoNetUsageItems := make([]*proto.NetUsageItem, 0)
	for _, partitionDetail := range partitionDetails {
		errs.Go(func() error {
			items, err := api.usageEngine.GetProtoNetUsageLineItems(gctx, api.logger, partitionDetail, costCenters, customerId)
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
	ctx, sp := api.tracer.Start(ctx, "UsageApi.GetUsageChartData")
	defer sp.End()

	ctx = config.CreateContextWithApiMetricName(ctx, config.GetUsageChartDataKey)
	// Get all cost centers and the partition details for each cost center
	costCenters, bpErr := api.getAllCostCentersForCustomer(ctx, input.UsageEntityId)
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

	partitionDetails, err := FromUsageChartRequestToUsagePartitionDetails(input, costCenters, topResourceIDs)
	if err != nil {
		return nil, err
	}

	api.logger.Info("Querying GetUsageChartData partition details", kvp.Int("billing.partitionDetailsLength", len(partitionDetails)), kvp.String(logging.BillingCustomerId, input.UsageEntityId))

	errs, gctx := errgroup.WithContext(ctx)
	partitionDetailsUsageItems := make([]models.PartitionDetailUsageItemResults, len(partitionDetails))
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
	ctx, sp := api.tracer.Start(ctx, "UsageApi.GetPaginatedUsageLineItems")
	defer sp.End()

	// Get all cost centers and the partition details for each cost center
	var costCenters []*models.CostCenter
	var bpErr error

	if input.CostCenterId == "" {
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

	api.logger.Info("Querying GetPaginatedUsageLineItems partition details", kvp.Int("billing.partitionDetailsLength", len(partitionDetails)), kvp.String(logging.BillingCustomerId, input.UsageEntityId))

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
		skipCache := false
		item.Pricing.UnitType, err = api.pricingEngine.GetUnitTypeForSku(ctx, api.logger, item.GetSku(), "GetEventItems", skipCache)
		if err != nil {
			return nil, err
		}

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

	usage, hitCache, err := api.discountEngine.GetDiscountTotal(ctx, api.logger, partitionDetail)
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

	skipCache := false
	unitType, err := api.pricingEngine.GetUnitTypeForSku(ctx, api.logger, partitionDetail.Sku, "GetDiscountTotal", skipCache)
	if err != nil {
		return nil, err
	}

	return &proto.GetDiscountTotalResponse{
		Sku:            partitionDetail.Sku,
		Quantity:       quantity,
		DiscountAmount: discountAmount,
		HitCache:       hitCache,
		UnitType:       unitType.ToProto(),
	}, nil
}

func (api *UsageApi) GetUsageTotal(ctx context.Context, input *proto.GetUsageRequest) (*proto.GetUsageResponse, error) {
	isFeatureFlagEnabled := api.flagger.IsEnabledWithDefaultValue(ctx, featureflags.UpdateGetUsageTotal, false, models.CustomerVexiActor(input.UsageEntityId))
	if isFeatureFlagEnabled {
		api.logger.Info("Request input pre-processing",
			kvp.String("request SKU", input.Sku))

		partitionDetail := &models.UsagePartitionDetail{
			UsageEntityId: input.UsageEntityId,
			UsageTime:     models.NewUsageTime().WithYear(input.Year),
			ActiveType:    models.Yearly,
		}
		usages, _ := api.usageEngine.GetUsageTotalItems(
			ctx,
			api.logger,
			partitionDetail,
			input.UsageEntityId,
			input.Year,
			input.Month,
		)
		var totalAmount int64
		var quantity int64
		for _, usage := range usages {
			amount := usage.Amounts
			totalAmount += amount.BilledAmount
			quantity += amount.Quantity
		}

		api.logger.Info("Item data",
			kvp.String("request", "GetUsageTotal"),
		)

		return &proto.GetUsageResponse{
			BillableAmount: models.ToDecimalAmount(totalAmount),
			Quantity:       models.ToDecimalAmount(quantity),
		}, nil
	} else {
		api.logger.Info("Request input pre-processing",
			kvp.String("request SKU", input.Sku))

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

		api.logger.Info("Item data",
			kvp.String("request", "GetUsageTotal"),
			kvp.String("partitionDetail.Sku", partitionDetail.Sku))

		skipCache := false
		unitType, err := api.pricingEngine.GetUnitTypeForSku(ctx, api.logger, partitionDetail.Sku, "GetUsageTotal", skipCache)
		if err != nil {
			return nil, err
		}

		return &proto.GetUsageResponse{
			Sku:            partitionDetail.Sku,
			BillableAmount: billableAmount,
			Quantity:       quantity,
			HitCache:       hitCache,
			UnitType:       unitType.ToProto(),
		}, nil
	}
}

func (api *UsageApi) GetEnterpriseUsageTotals(ctx context.Context, input *proto.GetEnterpriseUsageTotalsRequest) (*proto.GetEnterpriseUsageTotalsResponse, error) {
	costCenters, err := api.getAllCostCentersForCustomer(ctx, input.CustomerId)
	if err != nil {
		return nil, err
	}

	partitionDetails, err := FromEnterpriseUsageTotalsRequestToUsagePartitionDetails(input, costCenters)
	if err != nil {
		return nil, err
	}

	g, gctx := errgroup.WithContext(ctx)

	var usageItemMutex = &sync.Mutex{}
	var allItems []*models.Item
	isFeatureFlagEnabled := api.flagger.IsEnabledWithDefaultValue(ctx, featureflags.UpdateGetUsageTotal, false, models.CustomerVexiActor(input.CustomerId))
	for _, partitionDetail := range partitionDetails {
		g.Go(func(partitionDetail *models.UsagePartitionDetail) func() error {
			return func() error {
				var items []*models.Item
				var err error
				if isFeatureFlagEnabled {
					items, err = api.usageEngine.GetUsageTotalItems(gctx, api.logger, partitionDetail, partitionDetail.UsageEntityId, input.Year, input.Month)
				} else {
					items, err = api.usageEngine.GetEnterpriseUsageTotalItems(gctx, api.logger, partitionDetail, input)
				}

				if err != nil {
					return err
				}

				usageItemMutex.Lock()
				allItems = append(allItems, items...)
				usageItemMutex.Unlock()

				return nil
			}
		}(partitionDetail))
	}

	if err := g.Wait(); err != nil {
		return nil, errors.Wrap(err, "Failed to query enterprise usage totals")
	}

	usageTotals, err := api.usageService.BuildEnterpriseUsageTotals(input, allItems, costCenters)
	if err != nil {
		return nil, err
	}

	return usageTotals, nil
}

func (api *UsageApi) getAllCostCentersForCustomer(ctx context.Context, customerId string) ([]*models.CostCenter, error) {
	costCenters, bpErr := api.costCenterEngine.GetAllCostCentersFromCache(ctx, api.logger, models.NewCustomer(customerId))
	if bpErr != nil {
		api.logger.WithError(bpErr.OriginalError).Error(bpErr.FriendlyError.Error())
		return nil, bpErr.OriginalError
	}

	return costCenters, nil
}

// //////////////////////////////////////////////
// ////  GetUsageTotalTest //////////////////////
// //////////////////////////////////////////////
// This API is ONLY used in our integration tests and is not used in production.
// I'm keeping this around because some of our integration tests use it and
// there doesn't seem to be a good alternative to assert usage totals in the same way
// our tests expect. We should deprecate this either by mocking those integration tests
// finding a way to use our engines to get the same data (have we tried this before?)

func (api *UsageApi) GetUsageTotalTest(ctx context.Context, input *proto.GetUsageRequest) (*proto.GetUsageResponse, error) {
	api.logger.Info("Request input pre-processing",
		kvp.String("request SKU", input.Sku))

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

	api.logger.Info("Item data",
		kvp.String("request", "GetUsageTotal"),
		kvp.String("partitionDetail.Sku", partitionDetail.Sku))

	skipCache := false
	unitType, err := api.pricingEngine.GetUnitTypeForSku(ctx, api.logger, partitionDetail.Sku, "GetUsageTotal", skipCache)
	if err != nil {
		return nil, err
	}

	return &proto.GetUsageResponse{
		Sku:            partitionDetail.Sku,
		BillableAmount: billableAmount,
		Quantity:       quantity,
		HitCache:       hitCache,
		UnitType:       unitType.ToProto(),
	}, nil
}
