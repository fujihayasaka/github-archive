package handlers

import (
	"context"
	"encoding/json"
	"fmt"
	"strconv"

	"github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
	hydroSchema "github.com/github/billing-platform/generated/hydro/schemas/billingplatform/v1"
	hydroSchemaEntities "github.com/github/billing-platform/generated/hydro/schemas/billingplatform/v1/entities"
	"github.com/github/billing-platform/internal/nano"
	"github.com/github/billing-platform/lib/engines"
	"github.com/github/billing-platform/lib/messaging"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	stats "github.com/github/go-stats"
	schemas "github.com/github/hydro-client-go/v7/generated/hydro/v1"
	"github.com/pkg/errors"
	protobuf "google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/types/known/timestamppb"
)

type ZeroOutQuantitiesHandler struct {
	*Handler
	usageEngine engines.UsageEngineInterface
}

func NewZeroOutQuantitiesHandler(
	params *HandlerParams,
	usageEngine engines.UsageEngineInterface,
) *ZeroOutQuantitiesHandler {
	return &ZeroOutQuantitiesHandler{
		Handler:     NewHandler(params, models.WorkerTypeZeroOutQuantities),
		usageEngine: usageEngine,
	}
}

func (h *ZeroOutQuantitiesHandler) ProcessMessage(ctx context.Context, logger log.Logger, rr aqueduct.ReceiveResult) error {
	var jobRun *models.ZeroOutQuantitiesJobRun
	if err := json.Unmarshal(rr.Payload, &jobRun); err != nil {
		return errors.Wrap(err, "failed to unmarshal zero-out-quanities job run")
	}

	logger.Info("zeroing out backfill quantities for customer", kvp.String("customerId", jobRun.CustomerId))
	err := h.zeroOutBackfillForCustomer(ctx, logger, jobRun.CustomerId, jobRun.Sku, jobRun.Year, jobRun.Month)
	if err != nil {
		logger.Error("error processing zero-out job", kvp.String("error", err.Error()))
		return err
	}

	return nil
}

func (h *ZeroOutQuantitiesHandler) zeroOutBackfillForCustomer(ctx context.Context, logger log.Logger, customerId string, sku string, year string, month string) error {
	backfillArtifactEventsQuery := "SELECT * FROM c WHERE contains(c.SourceUri, 'backfill')"
	events, err := h.usageEngine.GetEventItemsByQuery(ctx, logger, backfillArtifactEventsQuery, fmt.Sprintf("%s:%s:events:%s:%s", customerId, sku, year, month))

	if err != nil {
		return err
	}
	logger.Info("zeroing out backfill events", kvp.String("length", fmt.Sprintf("%d", len(events))))
	h.statter.Counter("zero-out-job-events-found", stats.Tags{"customerId": customerId}, int64(len(events)))

	for _, event := range events {
		customerIdAsInt, _ := strconv.ParseInt(event.EntityDetail.CustomerId, 10, 64)

		negativeQuantity := nano.ToDecimalAmount[int64](event.Quantity * -1)

		usageAt := models.UTCNow()
		// TODO: if day is 1 here, yesterday will really mean today (i.e it's no-op)
		yesterday := usageAt.WithDay(usageAt.Day() - 1)
		// set UsageAt to yesterday to ensure the next rollup processes the negative event
		yesterdayTimestamp := &timestamppb.Timestamp{Seconds: yesterday.Unix(), Nanos: int32(yesterday.Nanosecond())}

		negativeUsageHydroEvent := &hydroSchema.Usage{
			Sku:       event.GetSku(),
			Quantity:  negativeQuantity,
			SourceUri: event.SourceUri,
			UsageAt:   yesterdayTimestamp,
			Entity: &hydroSchemaEntities.EntityDetail{
				CustomerId:     customerIdAsInt,
				OrganizationId: event.EntityDetail.OrganizationId,
				RepoId:         event.EntityDetail.RepositoryId,
				ActorId:        event.EntityDetail.ActorId,
			},
			UsageUuid: fmt.Sprintf("%d:%d:%d:%d:%d:%d:%d", customerIdAsInt, event.EntityDetail.OrganizationId, event.EntityDetail.RepositoryId, yesterday.Year(), yesterday.Month(), yesterday.Day(), yesterday.Hour()),
		}

		err := h.sendEvent(ctx, logger, negativeUsageHydroEvent)
		if err != nil {
			return errors.Wrap(err, fmt.Sprintf("error sending negative event to aqueduct %s", customerId))
		}

		h.statter.Counter("zero-out-job-event-sent", stats.Tags{"customerId": customerId}, 1)
	}
	logger.Info("zero-out-job-processed-for-customer", kvp.String("customerId", customerId))
	return nil
}

func (h *ZeroOutQuantitiesHandler) sendEvent(ctx context.Context, logger log.Logger, hydroEvent *hydroSchema.Usage) error {
	usageAsBytes, err := protobuf.Marshal(hydroEvent)
	if err != nil {
		return errors.Wrap(err, "error marshalling usage event")
	}

	envelope := schemas.Envelope{
		Message: usageAsBytes,
	}
	envelopeBytes, err := protobuf.Marshal(&envelope)
	if err != nil {
		return errors.Wrap(err, "error marshalling envelope")
	}

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
		l.WithError(err).Error("error submitting zero-out job to aqueduct")
	}

	return nil
}
