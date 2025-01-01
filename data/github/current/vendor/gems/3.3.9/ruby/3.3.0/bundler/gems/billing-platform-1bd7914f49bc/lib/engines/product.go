package engines

import (
	"context"

	"github.com/Azure/azure-sdk-for-go/sdk/data/azcosmos"
	"github.com/github/billing-platform/lib/db"
	"github.com/github/billing-platform/lib/interfaces"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/github-telemetry-go/log"
)

type ProductEngineInterface interface {
	GetAllProducts(ctx context.Context, logger log.Logger, skipCache bool) ([]*models.Product, error)
	Upsert(ctx context.Context, logger log.Logger, product *models.Product) error
	Get(ctx context.Context, logger log.Logger, productName string, skipCache bool) (*models.Product, error)
}

type ProductEngine struct {
	*EngineParams
}

func NewProductEngine(params *EngineParams) ProductEngineInterface {
	return &ProductEngine{
		EngineParams: params,
	}
}

func (p *ProductEngine) GetAllProducts(ctx context.Context, logger log.Logger, skipCache bool) ([]*models.Product, error) {
	var products []*models.Product
	var err error

	if skipCache {
		products, err = db.NewQuerier[*models.Product](p.db).QueryItems(ctx, logger, db.QueryStringAll, "product")
	} else {
		// Our default consistency level is session, but we want to read from the cache so we need to lax the
		// consistency level to eventual. The alternative would be to pass and manually manage the session token
		// ourselves which is not ideal and the Go SDK does not do this automatically as Azure documentation suggests.
		options := &azcosmos.QueryOptions{
			ConsistencyLevel: azcosmos.ConsistencyLevelEventual.ToPtr(),
		}
		products, err = db.NewGatewayQuerier[*models.Product](p.db).QueryItemsWithOptions(ctx, logger, db.QueryStringAll, "product", 0, options) // uses the query cache
	}

	if err != nil {
		return nil, err
	}

	return products, nil
}

func (p *ProductEngine) Upsert(ctx context.Context, logger log.Logger, product *models.Product) error {
	return p.db.UpsertWithOptions(ctx, logger, product, nil)
}

func (p *ProductEngine) Get(ctx context.Context, logger log.Logger, productName string, skipCache bool) (*models.Product, error) {
	productKey := models.NewProductKey(productName)

	var product *models.Product
	var err error

	if skipCache {
		product, err = db.NewQuerier[*models.Product](p.db).ReadItem(ctx, logger, productKey, nil)
	} else {
		// Our default consistency level is session, but we want to read from the cache so we need to lax the
		// consistency level to eventual. The alternative would be to pass and manually manage the session token
		// ourselves which is not ideal and the Go SDK does not do this automatically as Azure documentation suggests.
		options := &interfaces.QueryOptions{
			ConsistencyLevel: azcosmos.ConsistencyLevelEventual.ToPtr(),
		}
		product, err = db.NewGatewayQuerier[*models.Product](p.db).ReadItem(ctx, logger, productKey, options) // uses the item cache
	}

	if err != nil {
		return nil, err
	}

	return product, nil
}
