package api

import (
	"context"
	"sort"
	"sync"
	"time"

	"github.com/github/billing-platform/internal/featureflags"
	"github.com/github/billing-platform/lib/db"
	"github.com/github/billing-platform/lib/engines"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/billing-platform/lib/twirp/proto"
	"github.com/github/feature-management-client-go/vexi"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/pkg/errors"
	"github.com/twitchtv/twirp"
	"golang.org/x/sync/errgroup"
)

type UsageReportApi struct {
	costCenterEngine  engines.CostCenterEngineInterface
	usageEngine       engines.UsageEngineInterface
	pricingEngine     engines.PricingEngineInterface
	customerEngine    engines.CustomerEngineInterface
	usageReportEngine engines.UsageReportEngineInterface
	logger            log.Logger
	flagger           *vexi.Client
}

func NewUsageReportAPI(costCenterEngine engines.CostCenterEngineInterface, usageEngine engines.UsageEngineInterface, pricingEngine engines.PricingEngineInterface, customerEngine engines.CustomerEngineInterface, usageReportEngine engines.UsageReportEngineInterface, logger log.Logger, flagger *vexi.Client) *UsageReportApi {
	return &UsageReportApi{
		costCenterEngine:  costCenterEngine,
		usageEngine:       usageEngine,
		pricingEngine:     pricingEngine,
		customerEngine:    customerEngine,
		usageReportEngine: usageReportEngine,
		logger:            logger.Named("UsageReportApi"),
		flagger:           flagger,
	}
}

func (api *UsageReportApi) GetUsageReport(ctx context.Context, input *proto.GetUsageReportRequest) (*proto.GetUsageReportResponse, error) {
	usageReportStartTime := time.Now()

	partitionDetail, err := FromUsageReportRequestToUsagePartitionDetail(input)
	if err != nil {
		return nil, err
	}

	var usageItems []*models.Item
	var mutex = &sync.Mutex{}

	costCenterNames := make(map[string]string)
	discountAmountMap := make(map[string]float64)

	errs, gctx := errgroup.WithContext(ctx)

	if input.OrgId > 0 {
		customer, err := api.customerEngine.Get(ctx, api.logger, input.UsageEntityId, false)
		if err != nil {
			return nil, errors.Wrap(err, "Failed to query customer")
		}

		costCenterCachingEnabled := api.flagger.IsEnabledWithDefaultValue(ctx, featureflags.CostCenterQueryCaching, false, models.CustomerVexiActor(input.UsageEntityId))

		var costCenters []*models.CostCenter
		if costCenterCachingEnabled {
			tempCostCenters, bpErr := api.costCenterEngine.GetAllCostCentersFromCache(ctx, api.logger, customer)
			if bpErr != nil {
				api.logger.WithError(err).Error("error getting all cost centers")
				return nil, err
			}

			costCenters = tempCostCenters
		} else {
			tempCostCenters, bpErr := api.costCenterEngine.GetAllCostCenters(ctx, api.logger, customer)
			if bpErr != nil {
				api.logger.WithError(err).Error("error getting all cost centers")
				return nil, err
			}

			costCenters = tempCostCenters
		}

		for _, costCenter := range costCenters {
			costCenterNames[costCenter.CostCenterKey.UUID] = costCenter.Name
			costCenterInput := input
			costCenterInput.UsageEntityId = costCenter.CostCenterKey.UUID

			costCenterPartitionDetail, err := FromUsageReportRequestToUsagePartitionDetail(costCenterInput)
			if err != nil {
				return nil, err
			}

			errs.Go(func() error {
				costCenterUsageItems, err := api.usageEngine.GetUsageLineItemsForReport(gctx, api.logger, costCenterPartitionDetail, input.OrgId)
				if err != nil {
					return err
				}

				mutex.Lock()

				usageItems = append(usageItems, costCenterUsageItems...)
				mutex.Unlock()
				return nil
			})

			errs.Go(func() error {
				discountItems, err := api.usageEngine.GetDiscountLineItemsForReport(gctx, api.logger, costCenterPartitionDetail, input.OrgId)
				if err != nil {
					return err
				}

				for _, item := range discountItems {
					discountAmount := models.ToDecimalAmount(item.DiscountAmount)
					discountAmountMap[item.Id] = discountAmount
				}

				return nil
			})
		}
	}

	errs.Go(func() error {
		customerUsageItems, err := api.usageEngine.GetUsageLineItemsForReport(gctx, api.logger, partitionDetail, input.OrgId)
		if err != nil {
			return err
		}

		mutex.Lock()

		usageItems = append(usageItems, customerUsageItems...)
		mutex.Unlock()
		return nil
	})
	errs.Go(func() error {
		discountItems, err := api.usageEngine.GetDiscountLineItemsForReport(gctx, api.logger, partitionDetail, input.OrgId)
		if err != nil {
			return err
		}

		for _, item := range discountItems {
			discountAmount := models.ToDecimalAmount(item.DiscountAmount)
			discountAmountMap[item.Id] = discountAmount
		}

		return nil
	})

	if err := errs.Wait(); err != nil {
		return nil, errors.Wrap(err, "Failed to query report usage line items")
	}

	protoItems := make([]*proto.ReportItem, len(usageItems))
	for i, item := range usageItems {
		protoItems[i] = item.ToReportUsageProto(discountAmountMap[item.Id], costCenterNames)
	}

	sort.Slice(protoItems, func(i, j int) bool {
		if protoItems[i].UsageDate != protoItems[j].UsageDate {
			return protoItems[i].UsageDate < protoItems[j].UsageDate
		}

		return protoItems[i].Sku < protoItems[j].Sku
	})

	api.logger.Info("GetUsageReport request completed",
		kvp.String("usageEntityId", input.UsageEntityId),
		kvp.String("partitionKey", partitionDetail.ToGetLineItemsPartitionKey()),
		kvp.Int("numUsageItems", len(usageItems)),
		kvp.Int("numDiscountItems", len(discountAmountMap)),
		kvp.Duration("totalTime", time.Since(usageReportStartTime)),
	)

	return &proto.GetUsageReportResponse{
		ReportItems: protoItems,
	}, nil
}

func (api *UsageReportApi) QueueUsageReportExport(ctx context.Context, input *proto.QueueUsageReportExportRequest) (*proto.QueueUsageReportExportResponse, error) {
	hasActiveUsageReportExport, err := api.usageReportEngine.ActorHasActiveUsageReportExportForCustomer(ctx, api.logger, input.CustomerId, input.ActorId)
	if err != nil {
		return nil, err
	} else if hasActiveUsageReportExport {
		return nil, twirp.AlreadyExists.Error("User already has an active usage report export")
	}

	usageReportExport, err := api.usageReportEngine.CreateUsageReportExport(ctx, api.logger, input)
	if err != nil {
		if db.Is409Conflict(err) {
			return nil, twirp.AlreadyExists.Error("User already has an active usage report export")
		} else {
			return nil, err
		}
	}

	err = api.usageReportEngine.PublishUsageReportMessages(ctx, api.logger, []*models.UsageReportExport{usageReportExport})
	if err != nil {
		return nil, err
	}

	return &proto.QueueUsageReportExportResponse{}, nil
}
