package engines

import (
	"context"
	"fmt"

	"github.com/Azure/azure-sdk-for-go/sdk/data/azcosmos"
	"github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
	hydroSchema "github.com/github/billing-platform/generated/hydro/schemas/billingplatform/v1"
	"github.com/github/billing-platform/lib/db"
	"github.com/github/billing-platform/lib/interfaces"
	"github.com/github/billing-platform/lib/messaging"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/billing-platform/lib/twirp/proto"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	schemas "github.com/github/hydro-client-go/v5/generated/hydro/schemas/hydro/v1"
	protobuf "github.com/golang/protobuf/proto" //nolint:staticcheck
	"github.com/pkg/errors"
)

type SubscriptionsEngine struct {
	*EngineParams
	querier       interfaces.Querier[*models.SubscribedItem]
	totalPatching interfaces.TotalPatchingEngine
	logger        log.Logger
}

func NewSubscriptionsEngine(params *EngineParams, totalsPatching *TotalPatchingEngine, logger log.Logger) *SubscriptionsEngine {
	return newSubscriptionsEngineWithQuerier(params, db.NewQuerier[*models.SubscribedItem](params.db), totalsPatching, logger)
}

func newSubscriptionsEngineWithQuerier(
	params *EngineParams,
	querier interfaces.Querier[*models.SubscribedItem],
	totalPatching interfaces.TotalPatchingEngine,
	logger log.Logger) *SubscriptionsEngine {
	return &SubscriptionsEngine{
		EngineParams:  params,
		querier:       querier,
		totalPatching: totalPatching,
		logger:        logger,
	}
}

func (u *SubscriptionsEngine) ManageSubscription(ctx context.Context, subscribedItem *models.SubscribedItem) (isValidForBilling bool, err error) {
	// validate item
	if subscribedItem == nil {
		return false, nil
	}

	// check current state of subscription
	current, err := u.querier.ReadItem(ctx, u.logger, subscribedItem, nil)
	if err != nil {
		return false, err
	}

	if current == nil && subscribedItem.SubscriptionStatus == models.SubscriptionInactive {
		// if we get a remove and there was no license lets do nothing till we understand why we would get this.
		return false, fmt.Errorf("no license found to remove")
	}

	isValidForBilling = true
	// no subscription exists, create a new one
	if current == nil {
		created, err := u.db.CreateIfNotExists(ctx, u.logger, subscribedItem)
		if !created {
			return false, fmt.Errorf("failed to create even though there wasn't one. TODO handle this")
		} // to do handle race condtion if our create failed
		if err != nil {
			return false, err
		}
	} else {
		subscriptionUpdater := models.NewSubscriptionUpdater(current, subscribedItem)
		po := subscriptionUpdater.GetPatchOperations()
		isValidForBilling = subscriptionUpdater.IsValidForBilling()

		if err := u.db.PatchWithOptions(ctx, u.logger, current, po, nil); err != nil {
			u.logger.WithError(err).Error("could not patch subscription")
			return false, err
		}
	}

	amounts := models.NewAmountAsWholeNumbers(0, subscribedItem.SubscriptionStatus.ToQuantity())

	// if we upserted or created a new item, we need to update the total at the customer level
	// update global total as the subscription goes on or off
	total := &models.TotalItem{
		AmountsItem: &models.AmountsItem{
			Amounts: amounts,
			Key:     models.ToSubscriptionPartitionKeyActualCurrentTotal(subscribedItem.EntityDetail.CustomerId, subscribedItem.Sku),
		},
		IsTotal: true,
	}

	err = u.totalPatching.PatchOrCreate(ctx, u.logger, total)
	if err != nil {
		return false, err
	}

	return isValidForBilling, nil
}

func (u *SubscriptionsEngine) GetSubscribedItem(ctx context.Context, logger log.Logger, key *models.Key) (*models.SubscribedItem, error) {
	item, err := db.NewQuerier[*models.SubscribedItem](u.db).ReadItem(ctx, logger, key, nil)
	if err != nil {
		return nil, err
	}

	return item, nil
}

func (u *SubscriptionsEngine) GetSubscribedItems(ctx context.Context, logger log.Logger, req *proto.GetSubscribedItemsRequest) ([]*models.SubscribedItem, error) {
	key := models.ToSubscriptionPartitionKeyActualCurrentTotal(req.UsageEntityId, req.Sku)
	items, err := db.NewQuerier[*models.SubscribedItem](u.db).QueryItems(ctx, logger, db.QueryStringAllNontotal, key.PartitionKey)
	if err != nil {
		return nil, err
	}

	return items, nil
}

func (u *SubscriptionsEngine) GetActiveSubscribedItems(ctx context.Context, logger log.Logger, req *proto.GetSubscribedItemsRequest) ([]*models.SubscribedItem, error) {
	key := models.ToSubscriptionPartitionKeyActualCurrentTotal(req.UsageEntityId, req.Sku)
	queryString := db.QueryStringAllNontotal + fmt.Sprintf(" AND c.subscription_status = %d", models.SubscriptionActive)
	items, err := db.NewQuerier[*models.SubscribedItem](u.db).QueryItems(ctx, logger, queryString, key.PartitionKey)
	if err != nil {
		return nil, err
	}
	return items, nil
}

func (u *SubscriptionsEngine) GetSubscribedItemsTotal(ctx context.Context, logger log.Logger, req *proto.GetSubscribedItemsRequest) (*models.AmountsItem, error) {
	key := models.ToSubscriptionPartitionKeyActualCurrentTotal(req.UsageEntityId, req.Sku)

	querier := db.NewQuerier[*models.AmountsItem](u.db)
	total, err := querier.ReadItem(ctx, logger, key, nil)

	if err != nil {
		return nil, err
	}

	return total, nil
}

func (u *SubscriptionsEngine) GetSubscribedItemsMonthlyTotal(ctx context.Context, logger log.Logger, req *proto.GetSubscribedItemsMonthlyTotalRequest) (*models.AmountsItem, error) {
	usageAt := models.NewUsageTime().WithYear(req.Year).WithMonthInt(req.Month)
	highWatermark, err := u.GetHighWatermarkEvent(ctx, logger, req.UsageEntityId, req.Sku, *usageAt)
	if err != nil {
		return nil, err
	}
	if highWatermark == nil {
		return nil, nil
	}

	totalAmounts := &models.AmountsItem{
		Amounts: &models.Amounts{
			Quantity:     highWatermark.Quantity,
			BilledAmount: highWatermark.BilledAmount,
		},
		Key: &highWatermark.Key,
	}

	return totalAmounts, nil
}

func (u *SubscriptionsEngine) GetHighWatermarkEvent(ctx context.Context, logger log.Logger, usageEntityId, sku string, usageAt models.UsageTime) (*models.HighWatermarkEvent, error) {
	key := models.ToSubscriptionPartitionKeyForGivenMonthHighWaterMark(usageEntityId, sku, usageAt)
	querier := db.NewQuerier[*models.HighWatermarkEvent](u.db)
	return querier.ReadItem(ctx, logger, key, nil)
}

func (u *SubscriptionsEngine) IncrementDailyDiscountQuantity(ctx context.Context, logger log.Logger, highWatermarkEvent *models.HighWatermarkEvent) error {
	po := azcosmos.PatchOperations{}
	po.AppendIncrement("/DailyDiscountQuantity", highWatermarkEvent.DailyDiscountQuantity)

	return u.db.PatchWithOptions(ctx, logger, highWatermarkEvent, po, nil)
}

func (u *SubscriptionsEngine) SendToUsageIngestion(ctx context.Context, logger log.Logger, hydroEvent *hydroSchema.Usage) error {
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
		App:     u.cfg.AqueductApplication(),
		Queue:   messaging.GetQueueName(models.WorkerTypeUsageIngestion, u.cfg.OverrideQueuePrefix),
		Payload: envelopeBytes,
	}

	_, err = u.aqueductClient.Send(ctx, job, messaging.MessageSenderOptions()...)
	if err != nil {
		cause := "error sending job to aqueduct queue"
		logger.WithError(err).Error(cause, kvp.String("queue", job.Queue), kvp.String("payload", string(job.Payload)))
		return errors.Wrap(err, cause)
	}
	return nil
}
