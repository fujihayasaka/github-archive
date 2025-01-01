package api

import (
	"context"
	"errors"

	"github.com/github/billing-platform/internal/logging"
	"github.com/github/billing-platform/lib/bperrors"
	"github.com/github/billing-platform/lib/db"
	"github.com/github/billing-platform/lib/engines"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/billing-platform/lib/twirp/proto"
	"github.com/github/billing-platform/lib/utils"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"

	"github.com/twitchtv/twirp"
	"go.opentelemetry.io/otel/trace"
)

type CostCenterApi struct {
	costCenterEngine engines.CostCenterEngineInterface
	customerEngine   *engines.CustomerEngine
	logger           log.Logger
	tracer           trace.Tracer
}

func NewCostCenterAPI(costCenterEngine engines.CostCenterEngineInterface, customerEngine *engines.CustomerEngine, logger log.Logger, tracer trace.Tracer) *CostCenterApi {
	return &CostCenterApi{
		costCenterEngine: costCenterEngine,
		customerEngine:   customerEngine,
		logger:           logger.Named("CostCenterApi"),
		tracer:           tracer,
	}
}

// GetAllCostCenters implements proto.CostCenterApi
func (api *CostCenterApi) GetAllCostCenters(ctx context.Context, input *proto.GetAllCostCentersRequest) (*proto.GetAllCostCentersResponse, error) {
	var costCenters []*models.CostCenter
	var bpErr *bperrors.Error

	if input.UseCache {
		costCenters, bpErr = api.costCenterEngine.GetAllCostCentersFromCache(ctx, api.logger, models.NewCustomer(input.CustomerId))
	} else {
		costCenters, bpErr = api.costCenterEngine.GetAllCostCenters(ctx, api.logger, models.NewCustomer(input.CustomerId))
	}

	if bpErr != nil {
		api.logger.WithError(bpErr).Error("An unexpected error occurred in GetAllCostCenters", kvp.String(logging.BillingCustomerId, input.CustomerId))
		return nil, bpErr.ToTwirpError()
	}

	protoCostCenters := make([]*proto.CostCenter, len(costCenters))
	for i, costCenter := range costCenters {
		protoCostCenters[i] = costCenter.ToProto()
	}

	return &proto.GetAllCostCentersResponse{
		CostCenters: protoCostCenters,
	}, nil
}

// Get implements proto.CostCenterApi
func (api *CostCenterApi) GetCostCenter(ctx context.Context, request *proto.GetCostCenterRequest) (*proto.GetCostCenterResponse, error) {
	key := models.NewCostCenterKey(request.CostCenterKey, false)
	costCenter, err := api.costCenterEngine.Get(ctx, api.logger, key)
	if err != nil {
		return nil, err
	}

	if costCenter == nil {
		return &proto.GetCostCenterResponse{}, nil
	}

	return &proto.GetCostCenterResponse{
		CostCenter: costCenter.ToProto(),
	}, nil
}

func (api *CostCenterApi) CreateCostCenter(ctx context.Context, request *proto.CreateCostCenterRequest) (*proto.CreateCostCenterResponse, error) {
	costCenter := models.NewCostCenter(&proto.CostCenter{
		Name: request.Name,
		CostCenterKey: &proto.CostCenterKey{
			CustomerId: request.CustomerId,
			TargetId:   request.TargetId,
			TargetType: request.TargetType,
		},
		Resources: request.Resources,
	}, true)

	createdCostCenter, err := api.costCenterEngine.Create(ctx, api.logger, costCenter)
	if err != nil {
		if errors.Is(err, db.ItemConflictError) {
			return nil, twirp.NewError(twirp.AlreadyExists, "cannot create cost center")
		}

		if errors.Is(err, models.ErrorCostCenterConflict) {
			return nil, twirp.NewError(twirp.AlreadyExists, err.Error())
		}

		api.logger.WithError(err).Error("An unexpected error occurred in CreateCostCenter.", kvp.String(logging.BillingCustomerId, request.CustomerId), kvp.String(logging.BillingPlatformCostCenterName, request.Name))

		return nil, twirp.NewError(twirp.Internal, "An unexpected error occurred.")
	}

	customer := models.NewCustomerFromCostCenter(createdCostCenter.CostCenterKey)
	err = api.customerEngine.Upsert(ctx, api.logger, customer)
	if err != nil {
		return nil, err
	}

	return &proto.CreateCostCenterResponse{
		CostCenter: createdCostCenter.ToProto(),
	}, nil
}

func (api *CostCenterApi) UpdateCostCenter(ctx context.Context, request *proto.UpdateCostCenterRequest) (*proto.UpdateCostCenterResponse, error) {
	resourcesToAdd := utils.MapSlice(request.ResourcesToAdd, func(r *proto.Resource) *models.Resource {
		return models.NewResourceWith(r.Id, models.ToResourceType(r.Type))
	})
	resourcesToRemove := utils.MapSlice(request.ResourcesToRemove, func(r *proto.Resource) *models.Resource {
		return models.NewResourceWith(r.Id, models.ToResourceType(r.Type))
	})

	updatedCostCenter, err := api.costCenterEngine.Update(
		ctx,
		api.logger,
		models.NewCostCenterKey(request.Key, false),
		request.Name,
		request.TargetId,
		resourcesToAdd,
		resourcesToRemove,
		request.UpdateResourcesOnly,
	)

	if err != nil {
		if errors.Is(err, db.ItemConflictError) {
			return nil, twirp.NewError(twirp.AlreadyExists, "cannot update cost center")
		}

		if errors.Is(err, models.ErrorCostCenterConflict) {
			return nil, twirp.NewError(twirp.AlreadyExists, err.Error())
		}

		api.logger.WithError(err).Error("An unexpected error occurred in UpdateCostCenter.", kvp.String(logging.BillingCustomerId, request.Key.CustomerId), kvp.String(logging.BillingPlatformCostCenterName, request.Name))

		return nil, twirp.NewError(twirp.Internal, "An unexpected error occurred.")
	}

	customer := models.NewCustomerFromCostCenter(updatedCostCenter.CostCenterKey)
	err = api.customerEngine.Upsert(ctx, api.logger, customer)
	if err != nil {
		return nil, err
	}

	return &proto.UpdateCostCenterResponse{
		CostCenter: updatedCostCenter.ToProto(),
	}, nil
}

// AddResourceTo implements proto.CostCenterApi
func (api *CostCenterApi) AddResourceTo(ctx context.Context, request *proto.AddResourceToCostCenterRequest) (*proto.AddResourceToCostCenterResponse, error) {
	ctx, sp := api.tracer.Start(ctx, "CostCenterApi.AddResourceTo")
	defer sp.End()

	costCenterKey := models.NewCostCenterKey(request.Key, false)
	var resources []*models.Resource
	for _, resource := range request.Resources {
		resources = append(resources, models.NewResource(resource))
	}

	err := api.costCenterEngine.AddResourceTo(ctx, api.logger, costCenterKey, resources)
	if err != nil {
		return nil, err.ToTwirpError()
	}

	return &proto.AddResourceToCostCenterResponse{}, nil
}

// RemoveResourceFrom implements proto.CostCenterApi
func (api *CostCenterApi) RemoveResourceFrom(ctx context.Context, request *proto.RemoveResourceFromCostCenterRequest) (*proto.RemoveResourceFromCostCenterResponse, error) {
	costCenterKey := models.NewCostCenterKey(request.Key, false)
	costCenter, err := api.costCenterEngine.Get(ctx, api.logger, costCenterKey)
	if err != nil {
		return nil, bperrors.NewError(bperrors.Internal, err).ToTwirpError()
	}
	if costCenter == nil {
		return nil, api.notFoundError()
	}

	var resources []*models.Resource
	for _, resource := range request.Resources {
		resources = append(resources, models.NewResource(resource))
	}

	bpErr := api.costCenterEngine.RemoveResourceFrom(ctx, api.logger, costCenter, resources, true)
	if bpErr != nil {
		return nil, bpErr.ToTwirpError()
	}

	return &proto.RemoveResourceFromCostCenterResponse{}, nil
}

// FindFor implements proto.CostCenterApi
func (api *CostCenterApi) FindFor(ctx context.Context, request *proto.FindCostCenterForRequest) (*proto.FindCostCenterForResponse, error) {
	entity := models.NewEntityDetail(request.EntityDetail)

	// This is a temporary fix to unblock the licensing team from looking at the cost center data.
	// The idea behind this is that they will have a single cost center for seat based SKUs (GHEC, GHAS, Copilot),
	// so they will not be able to correctly decide which SKU to pass to the request.
	//
	// Future plan includes a new API that will return a cost center for a given resource.
	// For more, follow: https://github.com/github/gitcoin/issues/13219

	var sku string
	if request.Sku != "" {
		sku = request.Sku
	} else {
		sku = "copilot_for_business"
	}
	costCenterKey, err := api.costCenterEngine.FindCostCenterFor(ctx, api.logger, entity, sku)
	if err != nil {
		return nil, err
	}

	if costCenterKey == nil {
		return &proto.FindCostCenterForResponse{}, nil
	}

	return &proto.FindCostCenterForResponse{
		CostCenterKey: costCenterKey.ToProto(),
	}, nil
}

// ArchiveCostCenter implements proto.CostCenterApi
func (api *CostCenterApi) ArchiveCostCenter(ctx context.Context, request *proto.ArchiveCostCenterRequest) (*proto.ArchiveCostCenterResponse, error) {
	costCenterKey := models.NewCostCenterKey(request.CostCenterKey, false)

	// Set the Cost center customer doc to archived
	// example partition key: "customer:uuid"
	customer, err := api.customerEngine.Get(ctx, api.logger, costCenterKey.UUID)
	if err != nil {
		return nil, err
	}

	customer.CostCenterState = models.CostCenterArchived
	err = api.customerEngine.Upsert(ctx, api.logger, customer)
	if err != nil {
		return nil, err
	}

	// Set the Cost center doc to archived
	// example partition key: "customer:customerId:costCenters"
	// We want to be sure to do this after the customer because if we archive the cost center doc but the customer fails to archive
	// then we could end up in a state where it can't be archived again but the customer can still be charged.
	costCenter, err := api.costCenterEngine.Get(ctx, api.logger, costCenterKey)
	if err != nil {
		return nil, bperrors.NewError(bperrors.Internal, err).ToTwirpError()
	}
	if costCenter == nil {
		return nil, api.notFoundError()
	}

	bpErr := api.costCenterEngine.ArchiveCostCenter(ctx, api.logger, costCenter)
	if bpErr != nil {
		return nil, bpErr.ToTwirpError()
	}

	return &proto.ArchiveCostCenterResponse{}, nil
}

func (api *CostCenterApi) notFoundError() twirp.Error {
	return bperrors.NewError(bperrors.NotFound, errors.New("cost center not found")).ToTwirpError()
}
