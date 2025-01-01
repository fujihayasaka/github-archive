package engines

import (
	"context"
	"fmt"
	"time"

	"github.com/Azure/azure-sdk-for-go/sdk/data/azcosmos"
	"github.com/github/billing-platform/lib/db"
	"github.com/github/billing-platform/lib/interfaces"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	"github.com/pkg/errors"
)

type PricingEngineInterface interface {
	UpsertPricing(ctx context.Context, logger log.Logger, pricing *models.Pricing) (*models.Pricing, error)
	GetAllPricing(ctx context.Context, logger log.Logger, skipCache bool) ([]*models.Pricing, error)
	GetPricingsByProduct(ctx context.Context, logger log.Logger, productName string) ([]*models.Pricing, error)
	GetPricing(ctx context.Context, logger log.Logger, sku string, skipCache bool) (*models.Pricing, error)
	GetCurrentPricing(ctx context.Context, logger log.Logger, data *models.PricingSelectionData) *models.Pricing
	GetUnitTypeForSku(ctx context.Context, logger log.Logger, sku string, request string, skipCache bool) (models.UnitType, error)
	IsUnitTypeUserMonths(ctx context.Context, logger log.Logger, sku string, skipCache bool) (bool, error)
	IsHighWatermarkProduct(ctx context.Context, logger log.Logger, pricingTargetId string, skipCache bool) bool
	ApplyPricing(ctx context.Context, logger log.Logger, item interfaces.PricingApplicator) bool
}

type PricingEngine struct {
	*EngineParams
	pricingQuerier        interfaces.Querier[*models.Pricing]
	gatewayPricingQuerier interfaces.Querier[*models.Pricing]
}

func NewPricingEngine(params *EngineParams) *PricingEngine {
	return &PricingEngine{
		EngineParams:          params,
		pricingQuerier:        db.NewQuerier[*models.Pricing](params.db),
		gatewayPricingQuerier: db.NewGatewayQuerier[*models.Pricing](params.db),
	}
}

func NewPricingEngineWithQuerier(params *EngineParams, pricingQuerier interfaces.Querier[*models.Pricing], gatewayPricingQuerier interfaces.Querier[*models.Pricing]) PricingEngineInterface {
	return &PricingEngine{
		EngineParams:          params,
		pricingQuerier:        pricingQuerier,
		gatewayPricingQuerier: gatewayPricingQuerier,
	}
}

func (e *PricingEngine) ApplyPricing(ctx context.Context, logger log.Logger, item interfaces.PricingApplicator) bool {
	pricing := e.GetCurrentPricing(ctx, logger, &models.PricingSelectionData{ProductSku: item.GetSku()})

	foundPricing := pricing != nil
	if foundPricing {
		item.ApplyPricing(pricing)
	}

	return foundPricing
}

func (e *PricingEngine) UpsertPricing(ctx context.Context, logger log.Logger, pricing *models.Pricing) (*models.Pricing, error) {
	err := e.db.UpsertWithOptions(ctx, logger, pricing, nil)
	if err != nil {
		return nil, err
	}
	return pricing, nil
}

func (e *PricingEngine) GetAllPricing(ctx context.Context, logger log.Logger, skipCache bool) ([]*models.Pricing, error) {
	var pricings []*models.Pricing
	var err error

	start := time.Now()
	defer func() {
		duration := time.Since(start)
		e.statter.Timing("get_all_pricing", stats.Tags{}, duration)
	}()

	if skipCache {
		pricings, err = e.pricingQuerier.QueryItems(ctx, logger, db.QueryStringAll, "pricing")
	} else {
		// Our default consistency level is session, but we want to read from the cache so we need to lax the
		// consistency level to eventual. The alternative would be to pass and manually manage the session token
		// ourselves which is not ideal and the Go SDK does not do this automatically as Azure documentation suggests.
		options := &azcosmos.QueryOptions{
			ConsistencyLevel: azcosmos.ConsistencyLevelEventual.ToPtr(),
		}
		pricings, err = e.gatewayPricingQuerier.QueryItemsWithOptions(ctx, logger, db.QueryStringAll, "pricing", 0, options) // uses the item cache
	}

	if err != nil {
		return nil, err
	}

	if len(pricings) != 0 {
		return pricings, nil
	} else {
		return nil, errors.New("Failed to fetch all pricings")
	}
}

func (e *PricingEngine) GetPricingsByProduct(ctx context.Context, logger log.Logger, productName string) ([]*models.Pricing, error) {
	query := fmt.Sprintf("%s WHERE c.Product = \"%s\"", db.QueryStringAll, productName)
	pricings, err := db.NewQuerier[*models.Pricing](e.db).QueryItems(ctx, logger, query, "pricing")
	if err != nil {
		return nil, err
	}

	if len(pricings) != 0 {
		return pricings, nil
	} else {
		return nil, errors.New("Failed to fetch all pricings")
	}
}

func (e *PricingEngine) GetPricing(ctx context.Context, logger log.Logger, sku string, skipCache bool) (*models.Pricing, error) {
	key := models.NewPricingKey(sku)

	start := time.Now()
	defer func() {
		duration := time.Since(start)
		e.statter.Timing("get_pricing", stats.Tags{}, duration)
	}()

	var pricing *models.Pricing
	var err error

	if skipCache {
		pricing, err = e.pricingQuerier.ReadItem(ctx, logger, key, nil)
	} else {
		// Our default consistency level is session, but we want to read from the cache so we need to lax the
		// consistency level to eventual. The alternative would be to pass and manually manage the session token
		// ourselves which is not ideal and the Go SDK does not do this automatically as Azure documentation suggests.
		duration := time.Duration(24 * time.Hour)
		options := &interfaces.QueryOptions{
			ConsistencyLevel: azcosmos.ConsistencyLevelEventual.ToPtr(),
			DedicatedGatewayRequestOptions: &azcosmos.DedicatedGatewayRequestOptions{
				MaxIntegratedCacheStaleness: &duration,
			},
		}
		pricing, err = e.gatewayPricingQuerier.ReadItem(ctx, logger, key, options) // uses the item cache
	}

	if err != nil {
		return nil, err
	}

	if pricing == nil {
		// if pricing is nil and we attempted a read from the cache, we should query the database directly to be extra sure
		// that the pricing does not exist
		if !skipCache {
			e.statter.Counter("pricing.cache.miss", stats.Tags{"sku": sku}, 1)
			logger.Info("Pricing not found in cache, querying database", kvp.String("sku", sku))

			pricing, err = e.pricingQuerier.ReadItem(ctx, logger, key, nil)
			if err != nil {
				return nil, err
			} else if pricing != nil {
				return pricing, nil
			}
		}

		logger.Error("Pricing not found in database", kvp.String("sku", sku))
		return nil, err
	}

	return pricing, nil
}

// GetCurrentPricing implements interfaces.Pricing
func (e *PricingEngine) GetCurrentPricing(ctx context.Context, logger log.Logger, data *models.PricingSelectionData) *models.Pricing {
	pricing, err := e.GetPricing(ctx, logger, data.ProductSku, false)
	if err != nil {
		return nil
	}
	return pricing
}

func (e *PricingEngine) GetUnitTypeForSku(ctx context.Context, logger log.Logger, sku string, request string, skipCache bool) (models.UnitType, error) {
	pricing, err := e.GetPricing(ctx, logger, sku, skipCache)
	if err != nil || pricing == nil {
		return models.UnitTypeUnknown, errors.Wrap(err, fmt.Sprintf("failed to GetUnitTypeForSku from request %s", request))
	}

	return pricing.UnitType, nil
}

func (e *PricingEngine) IsUnitTypeUserMonths(ctx context.Context, logger log.Logger, sku string, skipCache bool) (bool, error) {
	if sku == "" {
		return false, nil
	}

	unitType, err := e.GetUnitTypeForSku(ctx, logger, sku, "isUnitTypeUserMonths", skipCache)
	if err != nil {
		return false, err
	}

	return unitType == models.UnitTypeUserMonths, nil
}

// This is used to determine which products/SKUs use "high watermark" business logic. It does not necessarily correlate
// with meter type. We use this list to determine whether a budget should be allowed to have isHardLimitBudget type.
// High watermark products are not allowed to have this budget type.
func (e *PricingEngine) IsHighWatermarkProduct(ctx context.Context, logger log.Logger, pricingTargetId string, skipCache bool) bool {
	highWatermarkProductList := []string{"copilot", "ghas", "ghec"}

	for _, value := range highWatermarkProductList {
		if value == pricingTargetId {
			return true
		}
	}

	isSkuUserMonth, _ := e.IsUnitTypeUserMonths(ctx, logger, pricingTargetId, skipCache)

	return isSkuUserMonth
}
