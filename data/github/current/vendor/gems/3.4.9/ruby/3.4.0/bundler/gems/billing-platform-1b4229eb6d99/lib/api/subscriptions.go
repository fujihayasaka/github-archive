// This handles calling item mappers and passing the results to the db and getting them back
package api

import (
	"context"
	"fmt"
	"strconv"
	"strings"
	"time"

	"github.com/github/billing-platform/internal/nano"
	"github.com/github/billing-platform/lib/config"
	"github.com/github/billing-platform/lib/engines"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/billing-platform/lib/twirp/proto"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	"google.golang.org/protobuf/types/known/timestamppb"

	hydroSchema "github.com/github/billing-platform/generated/hydro/schemas/billingplatform/v1"
	hydroSchemaEntities "github.com/github/billing-platform/generated/hydro/schemas/billingplatform/v1/entities"
)

type SubscriptionsApi struct {
	subscriptionsEngine *engines.SubscriptionsEngine
	logger              log.Logger
	cfg                 *config.Config
	statter             stats.Client
}

func NewSubscriptionsApi(subscriptionsEngine *engines.SubscriptionsEngine, logger log.Logger, cfg *config.Config, statter stats.Client) *SubscriptionsApi {
	return &SubscriptionsApi{
		subscriptionsEngine: subscriptionsEngine,
		logger:              logger.Named("SubscriptionsApi"),
		cfg:                 cfg,
		statter:             statter,
	}
}

func (s *SubscriptionsApi) GetSubscribedItem(ctx context.Context, req *proto.GetSubscribedItemRequest) (*proto.GetSubscribedItemResponse, error) {
	key := models.NewSubscribedItemKey(req.UsageEntityId, req.Sku, req.SubscriptionId)
	subscribedItem, err := s.subscriptionsEngine.GetSubscribedItem(ctx, s.logger, &key)
	if err != nil {
		return nil, err
	}

	if subscribedItem == nil {
		return &proto.GetSubscribedItemResponse{}, nil
	}

	return &proto.GetSubscribedItemResponse{
		SubscribedItem: subscribedItem.ToProto(),
	}, nil
}

func (s *SubscriptionsApi) GetSubscribedItems(ctx context.Context, req *proto.GetSubscribedItemsRequest) (*proto.GetSubscribedItemsResponse, error) {

	subscriptions, err := s.subscriptionsEngine.GetSubscribedItems(ctx, s.logger, req)
	if err != nil {
		return nil, err
	}

	var protoSubscriptions []*proto.SubscribedItem = []*proto.SubscribedItem{}
	for _, subscription := range subscriptions {
		// the items come from a partition with a "total" document. but in prod some of the "total" docs
		// might not have gotten the "total" field added to them yet. so we need to filter those out.
		// we might be able to take this away if we can get the "total" field added to all the docs. or do other clean up
		if strings.HasPrefix(subscription.Id, "subscription") {
			protoSubscriptions = append(protoSubscriptions, subscription.ToProto())
		}
	}

	return &proto.GetSubscribedItemsResponse{
		SubscribedItems: protoSubscriptions,
	}, nil
}

func (s *SubscriptionsApi) GetActiveSubscribedItems(ctx context.Context, req *proto.GetSubscribedItemsRequest) (*proto.GetSubscribedItemsResponse, error) {

	subscriptions, err := s.subscriptionsEngine.GetActiveSubscribedItems(ctx, s.logger, req)
	if err != nil {
		return nil, err
	}

	var protoSubscriptions []*proto.SubscribedItem = []*proto.SubscribedItem{}
	for _, subscription := range subscriptions {
		// the items come from a partition with a "total" document. but in prod some of the "total" docs
		// might not have gotten the "total" field added to them yet. so we need to filter those out.
		// we might be able to take this away if we can get the "total" field added to all the docs. or do other clean up
		if strings.HasPrefix(subscription.Id, "subscription") {
			protoSubscriptions = append(protoSubscriptions, subscription.ToProto())
		}
	}

	return &proto.GetSubscribedItemsResponse{
		SubscribedItems: protoSubscriptions,
	}, nil
}

func (s *SubscriptionsApi) GetSubscribedItemsTotal(ctx context.Context, req *proto.GetSubscribedItemsRequest) (*proto.GetSubscribedItemsTotalResponse, error) {
	total, err := s.subscriptionsEngine.GetSubscribedItemsTotal(ctx, s.logger, req)
	if err != nil {
		return nil, err
	}

	response := &proto.GetSubscribedItemsTotalResponse{}
	if total != nil {
		response.Quantity = nano.ToDecimalAmount[int64](total.Quantity)
		response.BilledAmount = nano.ToDecimalAmount[int64](total.BilledAmount)
	}

	return response, nil
}

func (s *SubscriptionsApi) GetSubscribedItemsMonthlyTotal(ctx context.Context, req *proto.GetSubscribedItemsMonthlyTotalRequest) (*proto.GetSubscribedItemsTotalResponse, error) {
	total, err := s.subscriptionsEngine.GetSubscribedItemsMonthlyTotal(ctx, s.logger, req)
	if err != nil {
		return nil, err
	}

	response := &proto.GetSubscribedItemsTotalResponse{}
	if total != nil {
		response.Quantity = nano.ToDecimalAmount[int64](total.Quantity)
		response.BilledAmount = nano.ToDecimalAmount[int64](total.BilledAmount)
	}

	return response, nil
}

func (s *SubscriptionsApi) AddLicense(ctx context.Context, req *proto.LicenseRequest) (*proto.LicenseResponse, error) {
	resp, err := s.doLicense(ctx, req, models.SubscriptionActive)
	if err != nil {
		s.statter.Counter("subscriptions_api.add_license.error", stats.Tags{"add_license_error": fmt.Sprintf("%v", err)}, 1)
	}
	return resp, err
}

func (s *SubscriptionsApi) RemoveLicense(ctx context.Context, req *proto.LicenseRequest) (*proto.LicenseResponse, error) {
	resp, err := s.doLicense(ctx, req, models.SubscriptionInactive)
	if err != nil {
		s.statter.Counter("subscriptions_api.remove_license.error", stats.Tags{"remove_license_error": fmt.Sprintf("%v", err)}, 1)
	}
	return resp, err
}

func (s *SubscriptionsApi) doLicense(ctx context.Context, req *proto.LicenseRequest, status models.SubscriptionStatus) (*proto.LicenseResponse, error) {
	if req == nil {
		return nil, fmt.Errorf("no license request provided")
	}

	subscribedItem := models.NewSubscribedItem(req, status)
	err := s.ProcessHighWatermark(ctx, s.logger, subscribedItem)

	if err != nil {
		return nil, err
	}

	return &proto.LicenseResponse{}, nil
}

func (s *SubscriptionsApi) ProcessHighWatermark(ctx context.Context, logger log.Logger, subscribedItem *models.SubscribedItem) error {
	customerIdAsInt, _ := strconv.ParseInt(string(subscribedItem.EntityDetail.CustomerId), 10, 64)
	// what time do we want to stamp the usage with?
	now := timestamppb.New(time.Now().UTC())
	usageUuid := fmt.Sprintf(
		"%d:%v:%d:%d:%d:%d",
		customerIdAsInt,
		subscribedItem.SubscriptionStatus.ToPrimaryKey(),
		now.AsTime().Year(), now.AsTime().Month(), now.AsTime().Day(), now.AsTime().Hour())

	usage := &hydroSchema.Usage{
		Sku:       subscribedItem.Sku,
		Quantity:  subscribedItem.SubscriptionStatus.ToQuantity(),
		SourceUri: models.InternallyProcessedEvent + ":" + subscribedItem.SubscriptionStatus.ToPrimaryKey(),
		UsageAt:   now,
		Entity: &hydroSchemaEntities.EntityDetail{
			CustomerId: customerIdAsInt,
			ActorId:    subscribedItem.EntityDetail.ActorId,
		},
		UsageUuid: usageUuid,
	}

	err := s.subscriptionsEngine.SendToUsageIngestion(ctx, logger, usage)

	return err

}
