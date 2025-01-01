package api

import (
	"context"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/licensify/internal/engines"
	"github.com/github/licensify/internal/models"
	proto "github.com/github/licensify/lib/twirp/proto/licensify/services/v1"
	"github.com/twitchtv/twirp"
)

// ProductEnablementAPI provides the API handlers for the ProductEnablement service.
type ProductEnablementAPI struct {
	productEnablementEngine *engines.ProductEnablementEngine
	logger                  log.Logger
}

// NewProductEnablementAPI creates a new ProductEnablementAPI.
func NewProductEnablementAPI(productEnablementEngine *engines.ProductEnablementEngine, logger log.Logger) *ProductEnablementAPI {
	return &ProductEnablementAPI{
		productEnablementEngine: productEnablementEngine,
		logger:                  logger.Named("ProductEnablementAPI"),
	}
}

// GetProductEnablements returns all product enablements for a customer.
func (api *ProductEnablementAPI) GetProductEnablements(ctx context.Context, request *proto.GetProductEnablementsRequest) (*proto.GetProductEnablementsResponse, error) {
	if request == nil {
		return nil, twirp.RequiredArgumentError("request")
	}
	if request.CustomerId == 0 {
		return nil, twirp.RequiredArgumentError("request.customerId")
	}

	productEnablements, err := api.productEnablementEngine.GetAll(ctx, api.logger, request.CustomerId)
	if err != nil {
		return nil, err
	}

	productEnablementProtos := make([]*proto.ProductEnablement, len(productEnablements))
	for i, pe := range productEnablements {
		productEnablementProtos[i] = pe.ToProto()
	}
	return &proto.GetProductEnablementsResponse{ProductEnablements: productEnablementProtos}, nil
}

// UpsertProductEnablement upserts a product enablement.
func (api *ProductEnablementAPI) UpsertProductEnablement(ctx context.Context, request *proto.UpsertProductEnablementRequest) (*proto.UpsertProductEnablementResponse, error) {
	if request == nil {
		return nil, twirp.RequiredArgumentError("request")
	}
	if request.ProductEnablement == nil {
		return nil, twirp.RequiredArgumentError("request.productEnablement")
	}
	if request.ProductEnablement.CustomerId == 0 {
		return nil, twirp.RequiredArgumentError("request.productEnablement.customerId")
	}
	if request.ProductEnablement.Product == proto.Product_PRODUCT_UNSPECIFIED {
		return nil, twirp.RequiredArgumentError("request.productEnablement.product")
	}
	if request.ProductEnablement.EnablementType == proto.ProductEnablementType_PRODUCT_ENABLEMENT_TYPE_UNSPECIFIED {
		return nil, twirp.RequiredArgumentError("request.productEnablement.enablementType")
	}
	if request.ProductEnablement.GlobalId == "" {
		return nil, twirp.RequiredArgumentError("request.productEnablement.globalId")
	}
	if request.ProductEnablement.EnabledAt == nil {
		return nil, twirp.RequiredArgumentError("request.productEnablement.enabledAt")
	}

	productEnablement := models.NewProductEnablementFromProto(request.ProductEnablement)
	err := api.productEnablementEngine.Upsert(ctx, api.logger, productEnablement, nil)
	if err != nil {
		return nil, err
	}

	return &proto.UpsertProductEnablementResponse{}, nil
}
