// This handles calling item mappers and passing the results to the db and getting them back
package api

import (
	"context"

	"github.com/github/billing-platform/lib/engines"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/billing-platform/lib/twirp/proto"
	"github.com/github/github-telemetry-go/log"
	"github.com/twitchtv/twirp"
)

type PricingApi struct {
	pricingEngine *engines.PricingEngine
	logger        log.Logger
}

func NewPricingAPI(pricingEngine *engines.PricingEngine, logger log.Logger) *PricingApi {
	return &PricingApi{
		pricingEngine: pricingEngine,
		logger:        logger.Named("PricingApi"),
	}
}

// UpsertPricing implements proto.PricingApi
func (api *PricingApi) UpsertPricing(ctx context.Context, request *proto.UpsertPricingRequest) (*proto.UpsertPricingResponse, error) {
	if request.Pricing == nil {
		return nil, twirp.RequiredArgumentError("pricing")
	}

	requestPricing := request.Pricing
	pricing, err := models.NewPricingFromProto(requestPricing)
	if err != nil {
		return nil, twirp.InvalidArgumentError("pricing", err.Error())
	}

	_, err = api.pricingEngine.UpsertPricing(ctx, api.logger, pricing)
	if err != nil {
		return nil, twirp.InternalErrorWith(err)
	}

	return &proto.UpsertPricingResponse{}, nil
}

// GetPricing implements proto.PricingApi
func (api *PricingApi) GetPricing(ctx context.Context, request *proto.GetPricingRequest) (*proto.GetPricingResponse, error) {
	if request.Sku == "" {
		return nil, twirp.RequiredArgumentError("sku")
	}

	pricing, err := api.pricingEngine.GetPricing(ctx, api.logger, request.Sku, true)
	if err != nil {
		return nil, twirp.InternalErrorWith(err)
	}

	if pricing == nil {
		return &proto.GetPricingResponse{}, nil
	}

	return &proto.GetPricingResponse{
		Pricing: pricing.ToProto(),
	}, nil
}

// GetAllPricing implements proto.PricingApi
func (api *PricingApi) GetAllPricing(ctx context.Context, request *proto.GetAllPricingRequest) (*proto.GetAllPricingResponse, error) {
	pricings, err := api.pricingEngine.GetAllPricing(ctx, api.logger)
	if err != nil {
		return nil, twirp.InternalErrorWith(err)
	}
	if pricings == nil {
		return &proto.GetAllPricingResponse{}, nil
	}

	var pricingProtos []*proto.Pricing

	for _, pricing := range pricings {
		p := pricing.ToProto()

		pricingProtos = append(pricingProtos, p)

	}

	return &proto.GetAllPricingResponse{
		Pricings: pricingProtos,
	}, nil
}

// GetPricingsByProduct implements proto.PricingApi
func (api *PricingApi) GetPricingsByProduct(ctx context.Context, request *proto.GetPricingsByProductRequest) (*proto.GetPricingsByProductResponse, error) {
	pricings, err := api.pricingEngine.GetPricingsByProduct(ctx, api.logger, request.ProductName)
	if err != nil {
		return nil, twirp.InternalErrorWith(err)
	}
	if pricings == nil {
		return &proto.GetPricingsByProductResponse{}, nil
	}

	var pricingProtos []*proto.Pricing
	for _, pricing := range pricings {
		p := pricing.ToProto()

		pricingProtos = append(pricingProtos, p)
	}

	return &proto.GetPricingsByProductResponse{
		Pricings: pricingProtos,
	}, nil
}
