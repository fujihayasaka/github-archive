package handlers

import (
	"context"
	"encoding/json"
	"fmt"
	"strconv"
	"strings"
	"sync"
	"time"

	hydroSchema "github.com/github/billing-platform/generated/hydro/schemas/billingplatform/v1"
	hydroSchemaEntities "github.com/github/billing-platform/generated/hydro/schemas/billingplatform/v1/entities"
	"github.com/github/billing-platform/internal/featureflags"
	"github.com/github/billing-platform/internal/logging"
	"github.com/github/billing-platform/internal/monolith"
	"github.com/github/billing-platform/internal/nano"
	"github.com/github/billing-platform/lib/engines"
	"github.com/github/billing-platform/lib/messaging"
	stats "github.com/github/go-stats"
	schemas "github.com/github/hydro-client-go/v7/generated/hydro/v1"
	"github.com/pkg/errors"
	"github.com/twitchtv/twirp"
	"golang.org/x/sync/errgroup"
	protobuf "google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/types/known/timestamppb"

	"github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"

	repositories "github.com/github/monolith-twirp-billing/repositories/v1"
	"golang.org/x/sync/semaphore"
)

type WatermarkHandler struct {
	*Handler
	customerEngine engines.CustomerEngineInterface
	usageEngine    engines.UsageEngineInterface
	pricingEngine  engines.PricingEngineInterface
	watermarkJob   *models.WatermarkJob
	discountEngine engines.DiscountEngineInterface
	monolithClient *monolith.Client
}

func NewWatermarkHandler(
	params *HandlerParams,
	customerEngine engines.CustomerEngineInterface,
	usageEngine engines.UsageEngineInterface,
	pricingEngine engines.PricingEngineInterface,
	discountEngine engines.DiscountEngineInterface,
	monolithClient *monolith.Client,
) *WatermarkHandler {
	return &WatermarkHandler{
		Handler:        NewHandler(params, models.WorkerTypeWatermarkHandler),
		customerEngine: customerEngine,
		usageEngine:    usageEngine,
		pricingEngine:  pricingEngine,
		discountEngine: discountEngine,
		monolithClient: monolithClient,
	}
}

func (h *WatermarkHandler) ProcessMessage(ctx context.Context, logger log.Logger, rr aqueduct.ReceiveResult) error {
	logger.Info("Processing message in", kvp.String("queue", h.queueName), kvp.Int("aqueduct.job_delivery_attempt", rr.DeliveryAttempt))
	h.statter.Counter("watermark.handler.process", stats.Tags{"delivery_attempt": fmt.Sprintf("%d", rr.DeliveryAttempt)}, 1)

	start := time.Now()
	defer func() {
		h.statter.Timing("watermark.handler.duration", stats.Tags{}, time.Since(start))
	}()

	ctx, sp := h.tracer.Start(ctx, "WatermarkHandler.ProcessMessage")
	defer sp.End()
	if success := h.validateHandlerDetails(ctx, logger, rr); !success {
		return nil
	}

	customerId := h.watermarkJob.ActiveCustomer.Id
	logger.Info("Successfully parsed the payload", kvp.String("customerID", customerId))

	// Spike work for https://github.com/github/gitcoin/issues/18758
	var quantityByEntityTotals *sync.Map
	shouldLogTotal := h.flagger.IsEnabledWithDefaultValue(ctx, featureflags.ShouldLogWatermarkTotals, false, models.CustomerVexiActor(customerId))
	if shouldLogTotal {
		logger.Info("Starting total watermark event rollups", kvp.String(logging.BillingCustomerId, customerId))
		h.statter.Counter("watermark_handler.count_customer_using_event_total", stats.Tags{}, int64(1))

		items, err := h.usageEngine.GetWatermarkEventTotals(ctx, logger, customerId, h.watermarkJob.PartitionDetail.Sku)
		if err != nil {
			// log the error but don't return
			logger.Error("Failed to fetch watermark event totals for customer", kvp.String(logging.BillingCustomerId, customerId))
		}

		quantityByEntityTotals = h.rollupsToMapForTotals(ctx, items)

		shouldEmitTotal := h.flagger.IsEnabledWithDefaultValue(ctx, featureflags.ShouldEmitWatermarkTotals, false, models.CustomerVexiActor(customerId))
		if shouldEmitTotal {
			logger.Info("emitting total", kvp.Any("customer", customerId))
			skipCache := false
			pricing, err := h.pricingEngine.GetPricing(ctx, logger, h.watermarkJob.PartitionDetail.Sku, skipCache)
			if err != nil {
				return err
			}

			lineItems := h.generateLineItems(ctx, quantityByEntityTotals, pricing, 0)
			err = h.emitLineItems(ctx, logger, rr, lineItems, customerId)
			if err != nil {
				return err
			}

			return nil
		}
	}

	logger.Info("Starting regular watermark process", kvp.String("customerID", customerId))
	rollups, err := h.usageEngine.GetWatermarkEventRollups(ctx, logger, customerId, h.watermarkJob.PartitionDetail.Sku)

	if err != nil {
		err := h.TrackErrorAndAddToDLQ(ctx, logger, rr, "customer.rollups", errors.Wrap(err, "Failed to retrieve rollups for active event customer"), true, kvp.String("customerID", customerId))
		if errors.Is(err, context.Canceled) {
			return err
		} else {
			return nil
		}
	}
	if len(rollups) == 0 {
		// active:events customers aren't cleaned up when they become inactive,
		// may be cases where we can't find rollups for them.
		_ = h.TrackErrorAndAddToDLQ(ctx, logger, rr, "customer.rollups", errors.New("No rollups found for active event customer"), false)
		return nil
	}

	firstRollup := rollups[0]
	sku := firstRollup.GetSku()

	if !firstRollup.IsEnabledForEmission() {
		_ = h.TrackErrorAndAddToDLQ(ctx, logger, rr, "rollup.is_enabled_for_emission", errors.New("Sku disabled for watermark processing"), false, kvp.String("sku", sku))
		return nil
	}

	if !h.IsRunInCurrentHour() {
		rollups = h.filterFutureRollups(rollups)
	}
	quantityByEntity := h.rollupsToMap(ctx, rollups)

	if shouldLogTotal {
		h.logTotals(logger, quantityByEntity, quantityByEntityTotals, sku)
	}

	lineItems := h.generateLineItems(ctx, quantityByEntity, firstRollup.Pricing, firstRollup.AppliedCostPerQuantity)

	logger.Info("calling emitLineItems", kvp.String("customerID", customerId))
	err = h.emitLineItems(ctx, logger, rr, lineItems, customerId)
	if err != nil {
		logger.WithError(err).Error("Failed to emit line items")
		return err
	}

	return nil
}

func (h *WatermarkHandler) logTotals(logger log.Logger, quantityByEntity *sync.Map, quantityByEntityTotals *sync.Map, sku string) {
	quantityByEntitySum := nano.NewFromInt(0)
	quantityByEntityTotalsSum := nano.NewFromInt(0)
	var customerId int64

	quantityByEntity.Range(func(k, v interface{}) bool {
		entityQuantity := v.(*nano.Nano)
		entityInfo := strings.Split(k.(string), ":")
		customerId, _ = strconv.ParseInt(entityInfo[0], 10, 64)
		orgId, _ := strconv.ParseInt(entityInfo[1], 10, 64)
		repoId, _ := strconv.ParseInt(entityInfo[2], 10, 64)

		logger.Info(
			"Watermark event:rollups",
			kvp.Int64(logging.BillingCustomerId, customerId),
			kvp.Int64(logging.OrganizationId, orgId),
			kvp.Int64(logging.RepositoryId, repoId),
			kvp.String(logging.BillingPlatformSku, sku),
			kvp.Int64("quantityByEntity", entityQuantity.Int64()),
		)

		quantityByEntitySum = quantityByEntitySum.Add(entityQuantity)

		return true
	})

	quantityByEntityTotals.Range(func(k, v interface{}) bool {
		entityQuantity := v.(*nano.Nano)
		entityInfo := strings.Split(k.(string), ":")
		customerId, _ = strconv.ParseInt(entityInfo[0], 10, 64)
		orgId, _ := strconv.ParseInt(entityInfo[1], 10, 64)
		repoId, _ := strconv.ParseInt(entityInfo[2], 10, 64)

		logger.Info(
			"Watermark event:rollups",
			kvp.Int64(logging.BillingCustomerId, customerId),
			kvp.Int64(logging.OrganizationId, orgId),
			kvp.Int64(logging.RepositoryId, repoId),
			kvp.String(logging.BillingPlatformSku, sku),
			kvp.Int64("quantityByEntityTotals", entityQuantity.Int64()),
		)

		quantityByEntityTotalsSum = quantityByEntityTotalsSum.Add(entityQuantity)

		return true
	})

	logger.Info(
		"Watermark event:rollups total diff",
		kvp.Int64(logging.BillingCustomerId, customerId),
		kvp.String(logging.BillingPlatformSku, sku),
		kvp.Int64("quantityByEntitySum", quantityByEntitySum.Int64()),
		kvp.Int64("quantityByEntityTotalsSum", quantityByEntityTotalsSum.Int64()),
	)
}

func (h *WatermarkHandler) validateHandlerDetails(ctx context.Context, logger log.Logger, rr aqueduct.ReceiveResult) bool {
	if err := json.Unmarshal(rr.Payload, &h.watermarkJob); err != nil {
		_ = h.TrackErrorAndAddToDLQ(ctx, logger, rr, "unmarshal.err", errors.New("Invalid json"), true)
		return false
	}

	if h.watermarkJob.ActiveCustomer == nil || h.watermarkJob.ActiveCustomer.Id == "" {
		_ = h.TrackErrorAndAddToDLQ(ctx, logger, rr, "customer.err", errors.New("Empty customer id"), true)
		return false
	}

	if h.watermarkJob.PartitionDetail == nil {
		_ = h.TrackErrorAndAddToDLQ(ctx, logger, rr, "partitionDetail.err", errors.New("Missing partition detail"), true)
		return false
	}

	if h.watermarkJob.JobRun == nil {
		_ = h.TrackErrorAndAddToDLQ(ctx, logger, rr, "jobRun.err", errors.New("Missing job run"), true)
		return false
	}

	return true
}

func (h *WatermarkHandler) IsRunInCurrentHour() bool {
	jobRunUsageTime := h.watermarkJob.JobRun.ToUsageTime()
	currentTime := models.NewUsageTime()

	return currentTime.Hour() == jobRunUsageTime.Hour() &&
		currentTime.Day() == jobRunUsageTime.Day() &&
		currentTime.Month() == jobRunUsageTime.Month() &&
		currentTime.Year() == jobRunUsageTime.Year()
}

// All rollups for a given customer are returned from the query. We need to filter out
// rollups from hours in the future of the current job run time. This is applicable for
// when we replay events from the DLQ to ensure we don't aggregate  incorrect quantities.
func (h *WatermarkHandler) filterFutureRollups(rollups []*models.Item) []*models.Item {
	var filteredRollups []*models.Item
	jobRunUsageTime := h.watermarkJob.JobRun.ToUsageTime()

	for _, rollup := range rollups {
		if rollup.UsageAt.StartOfHour().Before(jobRunUsageTime.StartOfHour()) || rollup.UsageAt.StartOfHour().Equal(jobRunUsageTime.StartOfHour()) {
			filteredRollups = append(filteredRollups, rollup)
		}
	}
	return filteredRollups
}

func (h *WatermarkHandler) rollupsToMapForTotals(ctx context.Context, rollupTotals []*models.WatermarkTotalItem) *sync.Map {
	_, rsp := h.tracer.Start(ctx, "WatermarkHandler.ProcessMessage.rollupsToMapForTotals")
	defer rsp.End()

	// I don't think it's really necessary to use a sync map here, since this is not being accessed by multiple goroutines. We should consider
	// refactoring this to use a regular map.
	var quantityByEntity sync.Map

	for _, rollupTotal := range rollupTotals {
		mapKey := fmt.Sprintf("%s:%d:%d", rollupTotal.EntityDetail.CustomerId, rollupTotal.EntityDetail.OrganizationId, rollupTotal.EntityDetail.RepositoryId)
		entityQuantity := nano.NewFromInt(rollupTotal.Quantity)

		quantityByEntity.Store(mapKey, entityQuantity)
	}

	return &quantityByEntity
}

func (h *WatermarkHandler) rollupsToMap(ctx context.Context, rollups []*models.Item) *sync.Map {
	_, rsp := h.tracer.Start(ctx, "WatermarkHandler.ProcessMessage.rollupsToMap")
	defer rsp.End()

	var quantityByEntity sync.Map

	// TODO: Unsure if this var is actually used anywhere in the loop
	customerBilledAmount := nano.NewFromInt(0)

	for _, rollup := range rollups {
		rollupTime := rollup.UsageAt
		mapKey := fmt.Sprintf("%s:%d:%d", rollup.EntityDetail.CustomerId, rollup.EntityDetail.OrganizationId, rollup.EntityDetail.RepositoryId)
		var entityQuantity *nano.Nano
		jobRunDay := h.watermarkJob.JobRun.ToUsageTime()

		sameDayRollup := rollupTime.StartOfDay() == jobRunDay.StartOfDay()
		// When it's 00:00, we need to look at the FractionalQuantity for the previous day
		startOfNextDay := jobRunDay.Hour() == 0 && jobRunDay.StartOfDay().Sub(rollupTime.StartOfDay()) == 24*time.Hour

		if sameDayRollup || startOfNextDay {
			entityQuantity = nano.NewFromInt(rollup.FractionalQuantity)
		} else {
			entityQuantity = nano.NewFromInt(rollup.Quantity)
		}

		entityQuantity = entityQuantity.Div(nano.NewFromInt(models.ToWholeAmount[int64](24)))

		// TODO: This block doesn't seem to be used anywhere, but it's not clear why
		price := nano.NewFromInt(rollup.GetPrice())
		effectiveBilledAmount := price.Mul(entityQuantity)
		customerBilledAmount = customerBilledAmount.Add(effectiveBilledAmount)

		val, _ := quantityByEntity.LoadOrStore(mapKey, nano.NewFromInt(0))
		finalVal := entityQuantity.Add(val.(*nano.Nano))
		quantityByEntity.Store(mapKey, finalVal)
	}

	return &quantityByEntity
}

func (h *WatermarkHandler) generateLineItems(ctx context.Context, quantityByEntity *sync.Map, pricing *models.Pricing, appliedCostPerQuantity int64) []*models.Item {
	_, gsp := h.tracer.Start(ctx, "WatermarkHandler.ProcessMessage.generateLineItems")
	defer gsp.End()

	var lineItems []*models.Item

	quantityByEntity.Range(func(k, v interface{}) bool {
		entityQuantity := v.(*nano.Nano)
		entityInfo := strings.Split(k.(string), ":")
		orgId, _ := strconv.ParseInt(entityInfo[1], 10, 64)
		repoId, _ := strconv.ParseInt(entityInfo[2], 10, 64)
		entityDetail := &models.EntityDetail{
			CustomerId:     entityInfo[0],
			OrganizationId: orgId,
			RepositoryId:   repoId,
		}

		lineItems = append(lineItems, &models.Item{
			Key:     *h.watermarkJob.ActiveCustomer,
			Pricing: pricing,
			UsageAt: *models.UTCNow(),
			Amounts: &models.Amounts{
				Quantity: entityQuantity.Int64(),
				// I don't think we need this?
				AppliedCostPerQuantity: appliedCostPerQuantity,
			},
			EntityDetail: entityDetail,
		})

		return true
	})

	h.statter.Counter("watermark_handler.count_customer_usage", stats.Tags{}, int64(len(lineItems)))

	return lineItems
}

func (h *WatermarkHandler) emitLineItems(ctx context.Context, logger log.Logger, rr aqueduct.ReceiveResult, lineItems []*models.Item, customerId string) error {
	ctx, esp := h.tracer.Start(ctx, "WatermarkHandler.ProcessMessage.emitLineItems")
	defer esp.End()

	logger.Info("emitLineItems", kvp.String("customerID", customerId))

	repositoryVisibilities, err := h.getRepositoryVisibilities(ctx, logger, lineItems)
	if err != nil {
		return err
	}

	if len(lineItems) > 0 {
		firstUsage := lineItems[0]
		for _, usage := range lineItems {
			if firstUsage.EntityDetail.CustomerId != usage.EntityDetail.CustomerId {
				logger.Info("customerId mismatch inside of the lineItems group", kvp.String("firstUsage.EntityDetail.CustomerId", firstUsage.EntityDetail.CustomerId), kvp.String("usage.EntityDetail.CustomerId", usage.EntityDetail.CustomerId))
			}
		}
	}

	shouldSendToThrottledWatermarkQueue := h.flagger.IsEnabledWithDefaultValue(ctx, featureflags.SendUsageToThrottledWatermarkQueue, false, models.CustomerVexiActor(customerId))
	jobRun := h.watermarkJob.JobRun
	for _, usage := range lineItems {
		if customerId != usage.EntityDetail.CustomerId {
			logger.Info("customerId mismatch", kvp.Bool("shouldSendToThrottledWatermarkQueue", shouldSendToThrottledWatermarkQueue), kvp.String("customerId", customerId), kvp.String("usage.EntityDetail.CustomerId", usage.EntityDetail.CustomerId))
		}

		customerIdAsInt, err := strconv.ParseInt(usage.EntityDetail.CustomerId, 10, 64)
		if err != nil {
			_ = h.TrackErrorAndAddToDLQ(ctx, logger, rr, "customer.err", err, true, kvp.String("customerID", customerId))
			return errors.Wrap(err, "Failed to parse customer id")
		}

		if usage.Amounts.Quantity <= 0 {
			h.statter.Counter("watermark_handler.negative_or_zero_quantity", stats.Tags{"product_sku": h.watermarkJob.PartitionDetail.Sku}, int64(1))
			continue
		}

		if usage.Amounts.BilledAmount < 0 {
			h.statter.Counter("watermark_handler.negative_or_zero_amount", stats.Tags{"product_sku": h.watermarkJob.PartitionDetail.Sku}, int64(1))
			continue
		}

		repositoryVisibility := hydroSchemaEntities.RepositoryVisibility_VISIBILITY_UNKNOWN
		if visibility, ok := repositoryVisibilities[usage.EntityDetail.RepositoryId]; ok {
			repositoryVisibility = visibility
		}

		// Create the lineItem for the Hour being processed
		usageAt := jobRun.ToUsageTime().StartOfHour()
		asHydroMessage := &hydroSchema.Usage{
			Sku:       usage.GetSku(),
			Quantity:  models.ToDecimalAmount[int64](usage.Quantity),
			SourceUri: models.InternallyProcessedEvent,
			UsageAt:   timestamppb.New(usageAt),
			Entity: &hydroSchemaEntities.EntityDetail{
				CustomerId:     customerIdAsInt,
				OrganizationId: usage.EntityDetail.OrganizationId,
				RepoId:         usage.EntityDetail.RepositoryId,
				ActorId:        usage.EntityDetail.ActorId,
			},
			UsageUuid:            fmt.Sprintf("%d:%s:%d:%d:%d:%d:%d:%d", customerIdAsInt, usage.GetSku(), usage.EntityDetail.OrganizationId, usage.EntityDetail.RepositoryId, jobRun.Year, jobRun.Month, jobRun.Day, jobRun.Hour),
			RepositoryVisibility: repositoryVisibility,
		}

		// Marshal the usage into JSON that matches hydroSchema.Usage
		usageAsBytes, err := protobuf.Marshal(asHydroMessage)
		if err != nil {
			logger.WithError(err).Error("Failed to marshal usage")
			return errors.Wrap(err, "Failed to marshal usage")
		}

		envelope := schemas.Envelope{
			Message: usageAsBytes,
		}
		envelopeBytes, err := protobuf.Marshal(&envelope)
		if err != nil {
			logger.WithError(err).Error("Failed to marshal envelope")
			return errors.Wrap(err, "Failed to marshal envelope")
		}

		// Send line items to the throttled watermark queue for test customers only
		if shouldSendToThrottledWatermarkQueue {
			logger.Info("sending the job to throttled watermark queue", kvp.String("customerId", customerId), kvp.String("usage.EntityDetail.CustomerId", usage.EntityDetail.CustomerId))
			job := aqueduct.Job{
				App:     h.cfg.AqueductApplication(),
				Queue:   messaging.GetQueueName(models.WorkerTypeThrottledWatermark, h.cfg.OverrideQueuePrefix),
				Payload: envelopeBytes,
			}
			_, err = h.aqueductClient.Send(ctx, job, messaging.MessageSenderOptions()...)
			if err != nil {
				l := logger.WithFields(
					kvp.String("aqueduct.job.app", job.App),
					kvp.String("aqueduct.job.queue", job.Queue),
					kvp.String("aqueduct.job.payload", string(usageAsBytes)),
				)
				l.WithError(err).Error("error submitting watermark to throttled watermark queue")
			}
		} else {
			// Send line items back to the usage ingestion handler
			job := aqueduct.Job{
				App:     h.cfg.AqueductApplication(),
				Queue:   messaging.GetQueueName(models.WorkerTypeUsageIngestion, h.cfg.OverrideQueuePrefix),
				Payload: envelopeBytes,
			}
			_, err = h.aqueductClient.Send(ctx, job, messaging.MessageSenderOptions()...)

			if err != nil {
				l := logger.WithFields(
					kvp.String("aqueduct.job.app", job.App),
					kvp.String("aqueduct.job.queue", job.Queue),
					kvp.String("aqueduct.job.payload", string(usageAsBytes)),
				)
				l.WithError(err).Error("error submitting watermark for usage ingestion")
				continue
			}
		}

		h.statter.Counter("watermark_handler.send_usage", stats.Tags{}, int64(1))
	}

	return nil
}

func (h *WatermarkHandler) getRepositoryVisibility(ctx context.Context, logger log.Logger, repoId int64) (hydroSchemaEntities.RepositoryVisibility, error) {
	ctx, sp := h.tracer.Start(ctx, "WatermarkHandler.ProcessMessage.getRepositoryVisibility")
	defer sp.End()

	if repoId == 0 {
		return hydroSchemaEntities.RepositoryVisibility_VISIBILITY_UNKNOWN, nil
	}

	var repoMetadata models.RepoMetadata

	repo, err := h.discountEngine.GetCachedRepositoryMetadata(ctx, logger, repoId)
	if (repo == nil) || (err != nil) {
		if err != nil {
			logger.WithError(err).Error("failed to get repo metadata from cache", kvp.Int64(logging.RepositoryId, repoId))
			if errors.Is(err, context.Canceled) {
				return hydroSchemaEntities.RepositoryVisibility_VISIBILITY_UNKNOWN, err
			}
		}

		h.statter.Counter("watermark.handler.get_repo_metadata", stats.Tags{}, int64(1))
		resp, err := h.monolithClient.RepositoryAPI.GetRepositoryMetadata(ctx, &repositories.GetRepositoryMetadataRequest{Id: uint64(repoId)})
		if err != nil {
			// check if "not found" is in the error since this is not an operational error and we can just return public visibility
			if twerr, ok := err.(twirp.Error); ok && twerr.Code() == twirp.NotFound {
				logger.WithError(err).Error("repo not found", kvp.Int64(logging.RepositoryId, repoId))

				// attempt to cache the repo metadata so we don't have to make this call again
				err = h.discountEngine.CacheRepositoryMetadata(ctx, logger, &repositories.Repository{
					Id: uint64(repoId),
					// store the repo with public of true so we don't accidentally bill for usage associated with
					// a deleted repo
					IsPublic: true,
				})
				if err != nil {
					logger.WithError(err).Info("unable to cache repo metadata")
				}

				return hydroSchemaEntities.RepositoryVisibility_PUBLIC, nil
			}

			return hydroSchemaEntities.RepositoryVisibility_VISIBILITY_UNKNOWN, errors.Wrap(err, "failed to get repo metadata")
		}

		err = h.discountEngine.CacheRepositoryMetadata(ctx, logger, resp.Repository)
		if err != nil {
			logger.WithError(err).Info("unable to cache repo metadata")
		}

		repoMetadata = resp.Repository
	} else {
		repoMetadata = repo
	}

	if repoMetadata.GetIsPublic() {
		return hydroSchemaEntities.RepositoryVisibility_PUBLIC, nil
	} else {
		return hydroSchemaEntities.RepositoryVisibility_VISIBILITY_UNKNOWN, nil
	}
}

// Query repository visibilities for the repositories in the line items if the line item product is free for public repos
func (h *WatermarkHandler) getRepositoryVisibilities(ctx context.Context, logger log.Logger, lineItems []*models.Item) (map[int64]hydroSchemaEntities.RepositoryVisibility, error) {
	ctx, sp := h.tracer.Start(ctx, "WatermarkHandler.ProcessMessage.getRepositoryVisibilities")
	defer sp.End()

	var repositoryVisibilities sync.Map
	for _, usage := range lineItems {
		repoID := usage.EntityDetail.RepositoryId
		repositoryVisibilities.Store(repoID, hydroSchemaEntities.RepositoryVisibility_VISIBILITY_UNKNOWN)
	}

	// if the line item(s) pricing is free for public repos, we need to query repo visibilities to apply public repo discounts if applicable
	if len(lineItems) > 0 && lineItems[0].Pricing.FreeForPublicRepos {
		sem := semaphore.NewWeighted(250)
		errs, gctx := errgroup.WithContext(ctx)

		for _, lineItem := range lineItems {
			err := sem.Acquire(ctx, 1)
			if err != nil {
				return nil, errors.Wrap(err, "failed to acquire semaphore")
			}

			errs.Go(func() error {
				defer sem.Release(1)

				visibility, err := h.getRepositoryVisibility(gctx, logger, lineItem.EntityDetail.RepositoryId)
				if err != nil {
					return err
				}

				repositoryVisibilities.Store(lineItem.EntityDetail.RepositoryId, visibility)

				return nil
			})
		}

		if err := errs.Wait(); err != nil {
			h.statter.Counter("watermark.handler.repository_visibilities_error", stats.Tags{"sku": lineItems[0].GetSku()}, int64(1))
			return nil, errors.Wrap(err, "failed to get repository visibilities")
		}
	}

	// Convert sync.Map to regular map
	result := make(map[int64]hydroSchemaEntities.RepositoryVisibility)
	repositoryVisibilities.Range(func(key, value interface{}) bool {
		result[key.(int64)] = value.(hydroSchemaEntities.RepositoryVisibility)
		return true
	})

	return result, nil
}

func (h *WatermarkHandler) TrackErrorAndAddToDLQ(ctx context.Context, logger log.Logger, rr aqueduct.ReceiveResult, reason string, err error, addToDlq bool, fields ...kvp.Field) error {
	logger.WithError(err).Error("error in watermark handler", fields...)
	h.statter.Counter("watermark_handler.error", stats.Tags{"origin": reason}, int64(1))
	if addToDlq {
		return h.AddToDeadLetterQueue(ctx, logger, rr.Payload, stats.Tags{"origin": reason})
	}

	return nil
}
