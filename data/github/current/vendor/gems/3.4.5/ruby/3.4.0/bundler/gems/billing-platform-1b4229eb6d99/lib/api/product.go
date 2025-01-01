package api

import (
	"context"
	"fmt"

	"github.com/github/billing-platform/lib/engines"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/billing-platform/lib/twirp/proto"
	"github.com/github/github-telemetry-go/log"
	"github.com/twitchtv/twirp"
)

type ProductApi struct {
	productEngine engines.ProductEngineInterface
	logger        log.Logger
}

func NewProductAPI(productEngine engines.ProductEngineInterface, logger log.Logger) *ProductApi {
	return &ProductApi{
		productEngine: productEngine,
		logger:        logger.Named("ProductApi"),
	}
}

func (api *ProductApi) GetAllProducts(ctx context.Context, request *proto.GetAllProductsRequest) (*proto.GetAllProductsResponse, error) {
	products, err := api.productEngine.GetAllProducts(ctx, api.logger, true)

	if err != nil {
		return nil, err
	}

	var returnedProducts []*proto.Product

	for _, product := range products {
		p := product.ToProto()

		returnedProducts = append(returnedProducts, p)
	}

	return &proto.GetAllProductsResponse{
		Products: returnedProducts,
	}, nil
}

func (api *ProductApi) UpsertProduct(ctx context.Context, request *proto.UpsertProductRequest) (*proto.UpsertProductResponse, error) {
	if request.Product == nil {
		return nil, fmt.Errorf("product invalid")
	}

	product := models.NewProduct(
		request.Product.Name,
		request.Product.FriendlyProductName,
		request.Product.ZuoraUsageIdentifier,
	)

	err := api.productEngine.Upsert(ctx, api.logger, product)
	if err != nil {
		return nil, err
	}

	return &proto.UpsertProductResponse{
		Product: product.ToProto(),
	}, nil
}

func (api *ProductApi) GetProduct(ctx context.Context, request *proto.GetProductRequest) (*proto.GetProductResponse, error) {
	product, err := api.productEngine.Get(ctx, api.logger, request.Product, true)
	if err != nil {
		return nil, err
	}

	if product == nil {
		return nil, twirp.NotFoundError("Product not found")
	}

	return &proto.GetProductResponse{
		Product: product.ToProto(),
	}, nil
}
