package transitions

import (
	"context"
	_ "embed"
	"encoding/json"
	"fmt"

	"github.com/github/billing-platform/lib/interfaces"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/github-telemetry-go/log"
)

//go:embed inputs/SkuList.json
var SkuList []byte

//go:embed inputs/ProductList.json
var ProductList []byte

type SkuToCosmosTransition struct {
	logger log.Logger
	db     interfaces.Database
}

type SKUItem struct {
	*models.Key
	Price              float64                 `json:"Price"`
	Sku                string                  `json:"Sku"`
	FriendlyName       string                  `json:"FriendlyName"`
	Product            string                  `json:"Product"`
	AzureMeterId       string                  `json:"AzureMeterId"`
	MeterType          models.PricingMeterType `json:"MeterType"`
	FreeForPublicRepos bool                    `json:"FreeForPublicRepos"`
	EffectiveAt        int64                   `json:"EffectiveAt"`
	UnitType           models.UnitType         `json:"UnitType"`
}

func NewSkuToCosmosTransition(
	logger log.Logger,
	db interfaces.Database,

) *SkuToCosmosTransition {
	return &SkuToCosmosTransition{
		logger: logger,
		db:     db,
	}
}

func (t *SkuToCosmosTransition) Run(ctx context.Context, dryRun bool, verbose bool) error {
	var skus map[string]SKUItem
	err := json.Unmarshal(SkuList, &skus)
	if err != nil {
		return fmt.Errorf("error unmarshaling the SKU JSON: %w", err)
	}

	for skuName, details := range skus {
		details.Key = &models.Key{
			PartitionKey: "pricing",
			Id:           skuName,
		}

		err := t.RunTransitionForSKUs(ctx, dryRun, details, verbose)
		if err != nil {
			return fmt.Errorf("error running transition for SKU %s: %w", skuName, err)
		}
	}

	var products map[string]models.Product
	err = json.Unmarshal(ProductList, &products)
	if err != nil {
		return fmt.Errorf("error unmarshaling the product JSON: %w", err)
	}

	for productName, details := range products {
		details.Key = &models.Key{
			PartitionKey: "product",
			Id:           productName,
		}

		err := t.RunTransitionForProduct(ctx, dryRun, details, verbose)
		if err != nil {
			return fmt.Errorf("error running transition for product %s: %w", productName, err)
		}
	}

	return nil
}

func (t *SkuToCosmosTransition) RunTransitionForSKUs(ctx context.Context, dryRun bool, sku SKUItem, verbose bool) error {
	if dryRun {
		t.logger.Info(
			"DRY RUN: Would have added SKU to Cosmos" + "\n" +
				"ItemKey Id: " + sku.GetKey().Id + "\n" +
				"Partition key: " + sku.GetKey().PartitionKey + "\n" +
				"Price: " + fmt.Sprintf("%f", sku.Price) + "\n" +
				"Sku: " + sku.Sku + "\n" +
				"FriendlyName: " + sku.FriendlyName + "\n" +
				"Product: " + sku.Product + "\n" +
				"AzureMeterId: " + sku.AzureMeterId + "\n" +
				"MeterType: " + fmt.Sprintf("%v", sku.MeterType) + "\n" +
				"FreeForPublicRepos: " + fmt.Sprintf("%t", sku.FreeForPublicRepos) + "\n" +
				"EffectiveAt: " + fmt.Sprintf("%d", sku.EffectiveAt) + "\n" +
				"UnitType: " + fmt.Sprintf("%v", sku.UnitType) + "\n" + "\n",
		)
	} else {
		skuPricing := &models.Pricing{
			Key:                sku.Key,
			Price:              models.ToWholeAmount[int64](sku.Price),
			Product:            sku.Product,
			Sku:                sku.Sku,
			MeterType:          sku.MeterType,
			FriendlyName:       sku.FriendlyName,
			AzureMeterId:       sku.AzureMeterId,
			FreeForPublicRepos: sku.FreeForPublicRepos,
			EffectiveAt:        sku.EffectiveAt,
			UnitType:           sku.UnitType,
		}

		if verbose {
			t.logger.Info(
				"RUN: Adding the following SKU to Cosmos" + "\n" +
					"ItemKey Id: " + skuPricing.GetKey().Id + "\n" +
					"Partition key: " + skuPricing.GetKey().PartitionKey + "\n" +
					"Price: " + fmt.Sprintf("%d", skuPricing.Price) + "\n" +
					"Sku: " + skuPricing.Sku + "\n" +
					"FriendlyName: " + skuPricing.FriendlyName + "\n" +
					"Product: " + skuPricing.Product + "\n" +
					"AzureMeterId: " + skuPricing.AzureMeterId + "\n" +
					"MeterType: " + fmt.Sprintf("%v", skuPricing.MeterType) + "\n" +
					"FreeForPublicRepos: " + fmt.Sprintf("%t", skuPricing.FreeForPublicRepos) + "\n" +
					"EffectiveAt: " + fmt.Sprintf("%d", skuPricing.EffectiveAt) + "\n" +
					"UnitType: " + fmt.Sprintf("%v", skuPricing.UnitType) + "\n" + "\n",
			)
		}
		_, err := t.db.CreateIfNotExists(ctx, t.logger, skuPricing)
		if err != nil {
			t.logger.WithError(err).Error("failed to create SKU pricing entry for: " + skuPricing.Sku)
		}
	}
	return nil
}

func (t *SkuToCosmosTransition) RunTransitionForProduct(ctx context.Context, dryRun bool, product models.Product, verbose bool) error {
	if dryRun {
		t.logger.Info(
			"DRY RUN: Would have added Product to Cosmos" + "\n" +
				"FriendlyName: " + product.FriendlyProductName + "\n" +
				"Name: " + product.Name + "\n" +
				"ZuoraUsageIdentifier: " + product.ZuoraUsageIdentifier + "\n",
		)
	} else {
		if verbose {
			t.logger.Info(
				"RUN: Adding the following SKU to Cosmos" + "\n" +
					"FriendlyName: " + product.FriendlyProductName + "\n" +
					"Name: " + product.Name + "\n" +
					"ZuoraUsageIdentifier: " + product.ZuoraUsageIdentifier + "\n",
			)
		}
		_, err := t.db.CreateIfNotExists(ctx, t.logger, product)
		if err != nil {
			t.logger.WithError(err).Error("failed to create product entry for: " + product.FriendlyProductName)
		}
	}
	return nil
}
