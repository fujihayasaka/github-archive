package engines

import (
	"context"
	"fmt"
	"reflect"
	"time"

	"github.com/Azure/azure-sdk-for-go/sdk/data/azcosmos"
	"github.com/github/billing-platform/lib/db"
	"github.com/github/billing-platform/lib/interfaces"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
)

type PricingSelectionData struct {
	TargetTime int64
	ProductSku string
	AccountId  int64
}

type PricingEngine struct {
	*EngineParams
}

func NewPricingEngine(params *EngineParams) *PricingEngine {
	return &PricingEngine{
		EngineParams: params,
	}
}

type PricingApplicator interface {
	ApplyPricing(currentPricing *models.Pricing)
	GetSku() string
}

func (e *PricingEngine) ApplyPricing(ctx context.Context, logger log.Logger, item PricingApplicator) bool {
	pricing := e.GetCurrentPricing(ctx, logger, &PricingSelectionData{ProductSku: item.GetSku()})
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

func (e *PricingEngine) GetAllPricing(ctx context.Context, logger log.Logger) ([]*models.Pricing, error) {
	pricings, err := db.NewQuerier[*models.Pricing](e.db).QueryItems(ctx, logger, db.QueryStringAll, "pricing")
	if err != nil {
		return nil, err
	}

	logger.Info("GetAllPricing", kvp.Int("pricing_count", len(pricings)))

	if len(pricings) != 0 {
		return pricings, nil
	}

	logger.Info("Getting all products")

	skus := AllProductSkuV2()
	for _, sku := range skus {
		p, err := models.NewPricingAsWholeAmountWithMeterType(sku.Sku, sku.Product, sku.Price, sku.MeterType, sku.FriendlyName, sku.AzureMeterId, []models.HistoricalPrice{}, sku.FreeForPublicRepos, sku.EffectiveAt, sku.UnitType)
		if err != nil {
			return nil, err
		}

		pricings = append(pricings, p)
	}

	return pricings, nil
}

func (e *PricingEngine) GetPricingsByProduct(ctx context.Context, logger log.Logger, productName string) ([]*models.Pricing, error) {
	query := fmt.Sprintf("%s WHERE c.Product = \"%s\"", db.QueryStringAll, productName)
	pricings, err := db.NewQuerier[*models.Pricing](e.db).QueryItems(ctx, logger, query, "pricing")
	if err != nil {
		return nil, err
	}

	if len(pricings) != 0 {
		return pricings, nil
	}

	logger.Info("Getting hardcoded pricing per product")

	skus := AllProductSkuV2()
	for _, sku := range skus {
		if sku.Product != productName {
			continue
		}
		p, err := models.NewPricingAsWholeAmountWithMeterType(sku.Sku, sku.Product, sku.Price, sku.MeterType, sku.FriendlyName, sku.AzureMeterId, []models.HistoricalPrice{}, sku.FreeForPublicRepos, sku.EffectiveAt, sku.UnitType)
		if err != nil {
			return nil, err
		}

		pricings = append(pricings, p)
	}

	return pricings, nil
}

func (e *PricingEngine) GetPricing(ctx context.Context, logger log.Logger, sku string, skipCache bool) (*models.Pricing, error) {
	key := models.NewPricingKey(sku)

	var pricingDatabase *models.Pricing
	var err error

	if skipCache {
		pricingDatabase, err = db.NewQuerier[*models.Pricing](e.db).ReadItem(ctx, logger, key, nil)
	} else {
		// Our default consistency level is session, but we want to read from the cache so we need to lax the
		// consistency level to eventual. The alternative would be to pass and manually manage the session token
		// ourselves which is not ideal and the Go SDK does not do this automatically as Azure documentation suggests.
		options := &interfaces.QueryOptions{
			ConsistencyLevel: azcosmos.ConsistencyLevelEventual.ToPtr(),
		}
		pricingDatabase, err = db.NewGatewayQuerier[*models.Pricing](e.db).ReadItem(ctx, logger, key, options) // uses the item cache
	}

	if err != nil {
		return nil, err
	}

	if pricingDatabase == nil {
		logger.Error("Pricing not found in database", kvp.String("sku", sku))
		return nil, err
	}

	logger.Info("Getting hardcoded pricing per sku")
	skuVal, ok := AllProductSkuV2()[sku]
	if ok {
		pricing, err := models.NewPricingAsWholeAmountWithMeterType(skuVal.Sku, skuVal.Product, float64(skuVal.Price), skuVal.MeterType, skuVal.FriendlyName, skuVal.AzureMeterId, []models.HistoricalPrice{}, skuVal.FreeForPublicRepos, skuVal.EffectiveAt, skuVal.UnitType)
		if err != nil {
			return nil, err
		}

		pricing.EffectiveDatePrices = nil
		if !reflect.DeepEqual(pricing, pricingDatabase) {
			e.statter.Counter("sku_mismatch", stats.Tags{"env": e.cfg.Environment, "sku": pricing.Sku}, int64(1))
			logger.Error("Hardcoded and database object are not deep equal!")
		} else {
			e.statter.Counter("sku_match", stats.Tags{"env": e.cfg.Environment, "sku": pricing.Sku}, int64(1))
		}
	}

	return pricingDatabase, nil
}

// GetCurrentPricing implements interfaces.Pricing
func (e *PricingEngine) GetCurrentPricing(ctx context.Context, logger log.Logger, data *PricingSelectionData) *models.Pricing {
	pricing, err := e.GetPricing(ctx, logger, data.ProductSku, false)
	if err == nil && pricing != nil {
		return pricing
	}

	if v2Pricing, ok := AllProductSkuV2()[data.ProductSku]; ok {
		pricing, err := models.NewPricingAsWholeAmountWithMeterType(
			v2Pricing.Sku,
			v2Pricing.Product,
			float64(v2Pricing.Price),
			v2Pricing.MeterType,
			"",
			v2Pricing.AzureMeterId,
			[]models.HistoricalPrice{},
			v2Pricing.FreeForPublicRepos,
			v2Pricing.EffectiveAt,
			v2Pricing.UnitType,
		)
		if err == nil {
			return pricing
		}
	}

	return nil
}

func (e *PricingEngine) GetUnitTypeForSku(sku string) models.UnitType {
	skus := AllProductSkuV2()
	pricing, ok := skus[sku]
	if !ok {
		return models.UnitTypeUnknown
	}

	return pricing.UnitType
}

func (e *PricingEngine) IsUnitTypeUserMonths(sku string) bool {
	if sku == "" {
		return false
	}

	unitType := e.GetUnitTypeForSku(sku)

	return unitType == models.UnitTypeUserMonths
}

// TODO move to DB
func AllProductSkuV2() map[string]models.OldPrice {
	// Actions is rolled out for all customers with "actions" product enabled
	actionsRolloutEffectiveAt := time.Date(2023, 7, 14, 20, 30, 0, 0, time.UTC).Unix()
	// git_lfs_bandwidth is rolled out for all customers with "git_lfs" product enabled
	lfsBandwidthRolloutEffectiveAt := time.Date(2023, 8, 18, 10, 0, 0, 0, time.UTC).Unix()
	// git_lfs_storage is rolled out for all customers with "git_lfs" product enabled
	lfsStorageRolloutEffectiveAt := time.Date(2023, 8, 22, 18, 0, 0, 0, time.UTC).Unix()
	// copilot_for_business is rolled out for all customers with "copilot" product enabled
	copilotForBusinessRolloutEffectiveAt := time.Date(2023, 9, 5, 18, 0, 0, 0, time.UTC).Unix()
	// copilot_enterprise is rolled out for all customers with "copilot" product enabled
	copilotEnterpriseRolloutEffectiveAt := time.Date(2024, 4, 1, 18, 0, 0, 0, time.UTC).Unix()
	// copilot_standalone is rolled out for all customers with "copilot" product enabled
	copilotStandaloneRolloutEffectiveAt := time.Date(2024, 5, 1, 18, 0, 0, 0, time.UTC).Unix()
	// ghec_seats is rolled out for all customers with "ghec" product enabled
	ghecRolloutEffectiveAt := time.Date(2023, 9, 5, 18, 0, 0, 0, time.UTC).Unix()
	// ghas_seats is rolled out for all customers with "ghas" product enabled
	ghasRolloutEffectiveAt := time.Date(2023, 11, 1, 1, 0, 0, 0, time.UTC).Unix()
	// codespaces is rolled out for beta customers with "codespaces" product enabled
	codespacesRolloutEffectiveAt := time.Date(2024, 3, 0, 1, 0, 0, 0, time.UTC).Unix()
	// packages is rolled out for beta customers with "packages" product enabled
	packagesRolloutEffectiveAt := time.Date(2024, 5, 1, 0, 0, 0, 0, time.UTC).Unix()

	// This is for all remaining SKUs that are not yet rolled out
	disabledRolloutEffectiveAt := time.Date(9999, 12, 31, 0, 0, 0, 0, time.UTC).Unix()

	pricings := map[string]models.OldPrice{
		// Actions rollout
		"actions_linux":              {Price: 0.008, Sku: "actions_linux", FriendlyName: "Actions Linux", Product: "actions", AzureMeterId: "3dbfec75-284c-4c89-8c9c-0d395be81a0c", MeterType: models.PricingMeterDefault, FreeForPublicRepos: true, EffectiveAt: actionsRolloutEffectiveAt, UnitType: models.UnitTypeMinutes},
		"actions_linux_16_core":      {Price: 0.064, Sku: "actions_linux_16_core", FriendlyName: "Actions Linux 16-core", Product: "actions", AzureMeterId: "cdc3163b-3623-5f85-9c2b-980c77501091", MeterType: models.PricingMeterDefault, FreeForPublicRepos: false, EffectiveAt: actionsRolloutEffectiveAt, UnitType: models.UnitTypeMinutes},
		"actions_linux_32_core":      {Price: 0.128, Sku: "actions_linux_32_core", FriendlyName: "Actions Linux 32-core", Product: "actions", AzureMeterId: "8a019f97-b29d-54e1-9cff-ca30b7b7bdca", MeterType: models.PricingMeterDefault, FreeForPublicRepos: false, EffectiveAt: actionsRolloutEffectiveAt, UnitType: models.UnitTypeMinutes},
		"actions_linux_4_core":       {Price: 0.016, Sku: "actions_linux_4_core", FriendlyName: "Actions Linux 4-core", Product: "actions", AzureMeterId: "c99174a9-29ab-523c-94ee-17f79f0880f2", MeterType: models.PricingMeterDefault, FreeForPublicRepos: false, EffectiveAt: actionsRolloutEffectiveAt, UnitType: models.UnitTypeMinutes},
		"actions_linux_64_core":      {Price: 0.256, Sku: "actions_linux_64_core", FriendlyName: "Actions Linux 64-core", Product: "actions", AzureMeterId: "b49e6a8f-dd7c-5738-9050-884c5d3c52b4", MeterType: models.PricingMeterDefault, FreeForPublicRepos: false, EffectiveAt: actionsRolloutEffectiveAt, UnitType: models.UnitTypeMinutes},
		"actions_linux_8_core":       {Price: 0.032, Sku: "actions_linux_8_core", FriendlyName: "Actions Linux 8-core", Product: "actions", AzureMeterId: "ab699233-b084-59c7-a03c-a310a964d1a6", MeterType: models.PricingMeterDefault, FreeForPublicRepos: false, EffectiveAt: actionsRolloutEffectiveAt, UnitType: models.UnitTypeMinutes},
		"actions_macos":              {Price: 0.08, Sku: "actions_macos", FriendlyName: "Actions macOS 3-core", Product: "actions", AzureMeterId: "ca27e6bd-82cd-4cca-b015-818d85ae75a9", MeterType: models.PricingMeterDefault, FreeForPublicRepos: true, EffectiveAt: actionsRolloutEffectiveAt, UnitType: models.UnitTypeMinutes},
		"actions_macos_12_core":      {Price: 0.32, Sku: "actions_macos_12_core", FriendlyName: "Actions macOS 12-core", Product: "actions", AzureMeterId: "8e1a3725-ca5d-5785-bac4-0950888e1385", MeterType: models.PricingMeterDefault, FreeForPublicRepos: false, EffectiveAt: actionsRolloutEffectiveAt, UnitType: models.UnitTypeMinutes},
		"actions_macos_8_core":       {Price: 0.32, Sku: "actions_macos_8_core", FriendlyName: "Actions macOS 8-core", Product: "actions", AzureMeterId: "8e1a3725-ca5d-5785-bac4-0950888e1385", MeterType: models.PricingMeterDefault, FreeForPublicRepos: false, EffectiveAt: actionsRolloutEffectiveAt, UnitType: models.UnitTypeMinutes},
		"actions_macos_l":            {Price: 0.12, Sku: "actions_macos_l", FriendlyName: "Actions macOS Large", Product: "actions", AzureMeterId: "9f2f9fcb-49df-5a30-8372-e4790567389f", MeterType: models.PricingMeterDefault, FreeForPublicRepos: false, EffectiveAt: actionsRolloutEffectiveAt, UnitType: models.UnitTypeMinutes},
		"actions_macos_xl":           {Price: 0.16, Sku: "actions_macos_xl", FriendlyName: "Actions macOS XLarge", Product: "actions", AzureMeterId: "5eab894d-7573-5e7d-ac4b-cc3efa1f47b3", MeterType: models.PricingMeterDefault, FreeForPublicRepos: false, EffectiveAt: actionsRolloutEffectiveAt, UnitType: models.UnitTypeMinutes},
		"actions_windows":            {Price: 0.016, Sku: "actions_windows", FriendlyName: "Actions Windows", Product: "actions", AzureMeterId: "cc383714-48b2-46c6-aa9d-62040318c9e0", MeterType: models.PricingMeterDefault, FreeForPublicRepos: true, EffectiveAt: actionsRolloutEffectiveAt, UnitType: models.UnitTypeMinutes},
		"actions_windows_16_core":    {Price: 0.128, Sku: "actions_windows_16_core", FriendlyName: "Actions Windows 16-core", Product: "actions", AzureMeterId: "827229f1-6fc4-5259-86fc-58fe940d20cf", MeterType: models.PricingMeterDefault, FreeForPublicRepos: false, EffectiveAt: actionsRolloutEffectiveAt, UnitType: models.UnitTypeMinutes},
		"actions_windows_32_core":    {Price: 0.256, Sku: "actions_windows_32_core", FriendlyName: "Actions Windows 32-core", Product: "actions", AzureMeterId: "d4062bcc-b765-54b1-b5cb-be5776895e69", MeterType: models.PricingMeterDefault, FreeForPublicRepos: false, EffectiveAt: actionsRolloutEffectiveAt, UnitType: models.UnitTypeMinutes},
		"actions_windows_4_core":     {Price: 0.032, Sku: "actions_windows_4_core", FriendlyName: "Actions Windows 4-core", Product: "actions", AzureMeterId: "fe67b21a-12af-55a5-ac5d-9b8e4da5686b", MeterType: models.PricingMeterDefault, FreeForPublicRepos: false, EffectiveAt: actionsRolloutEffectiveAt, UnitType: models.UnitTypeMinutes},
		"actions_windows_64_core":    {Price: 0.512, Sku: "actions_windows_64_core", FriendlyName: "Actions Windows 64-core", Product: "actions", AzureMeterId: "7593218e-ee68-50e3-8dd9-d15316b4bca5", MeterType: models.PricingMeterDefault, FreeForPublicRepos: false, EffectiveAt: actionsRolloutEffectiveAt, UnitType: models.UnitTypeMinutes},
		"actions_windows_8_core":     {Price: 0.064, Sku: "actions_windows_8_core", FriendlyName: "Actions Windows 8-core", Product: "actions", AzureMeterId: "339d9fa4-b613-501a-b019-539174569ca6", MeterType: models.PricingMeterDefault, FreeForPublicRepos: false, EffectiveAt: actionsRolloutEffectiveAt, UnitType: models.UnitTypeMinutes},
		"actions_linux_4_core_gpu":   {Price: 0.07, Sku: "actions_linux_4_core_gpu", FriendlyName: "Actions Linux GPU 4-core", Product: "actions", AzureMeterId: "3dcbc93d-23b4-527c-b822-b631dc7f998a", MeterType: models.PricingMeterDefault, FreeForPublicRepos: false, EffectiveAt: actionsRolloutEffectiveAt, UnitType: models.UnitTypeMinutes},
		"actions_windows_4_core_gpu": {Price: 0.14, Sku: "actions_windows_4_core_gpu", FriendlyName: "Actions Windows GPU 4-core", Product: "actions", AzureMeterId: "1b20f01b-da75-571a-996d-009fccc25531", MeterType: models.PricingMeterDefault, FreeForPublicRepos: false, EffectiveAt: actionsRolloutEffectiveAt, UnitType: models.UnitTypeMinutes},

		// Effective date for ARM SKUs for real customers is 2024-01-02
		// Azure meter IDs are not yet available for ARM SKUs. We're using the Azure meter for regular SKU of same sizes for now.
		"actions_linux_2_core_arm":    {Price: 0.005, Sku: "actions_linux_2_core_arm", FriendlyName: "Actions Linux ARM 2-core", Product: "actions", AzureMeterId: "fd5a353c-bf0f-58ba-8678-e55abcf623a4", MeterType: models.PricingMeterDefault, FreeForPublicRepos: false, EffectiveAt: actionsRolloutEffectiveAt, UnitType: models.UnitTypeMinutes},
		"actions_linux_4_core_arm":    {Price: 0.01, Sku: "actions_linux_4_core_arm", FriendlyName: "Actions Linux ARM 4-core", Product: "actions", AzureMeterId: "86fdbab6-3efc-5f01-b2d4-42822322bb19", MeterType: models.PricingMeterDefault, FreeForPublicRepos: false, EffectiveAt: actionsRolloutEffectiveAt, UnitType: models.UnitTypeMinutes},
		"actions_linux_8_core_arm":    {Price: 0.02, Sku: "actions_linux_8_core_arm", FriendlyName: "Actions Linux ARM 8-core", Product: "actions", AzureMeterId: "8a421679-c543-5960-90e9-2a35b30a70a3", MeterType: models.PricingMeterDefault, FreeForPublicRepos: false, EffectiveAt: actionsRolloutEffectiveAt, UnitType: models.UnitTypeMinutes},
		"actions_linux_16_core_arm":   {Price: 0.04, Sku: "actions_linux_16_core_arm", FriendlyName: "Actions Linux ARM 16-core", Product: "actions", AzureMeterId: "64352e57-6b46-51b7-9c92-d8c895f7e707", MeterType: models.PricingMeterDefault, FreeForPublicRepos: false, EffectiveAt: actionsRolloutEffectiveAt, UnitType: models.UnitTypeMinutes},
		"actions_linux_32_core_arm":   {Price: 0.08, Sku: "actions_linux_32_core_arm", FriendlyName: "Actions Linux ARM 32-core", Product: "actions", AzureMeterId: "ef6f0042-714d-5495-a1fb-813eaf6a5a44", MeterType: models.PricingMeterDefault, FreeForPublicRepos: false, EffectiveAt: actionsRolloutEffectiveAt, UnitType: models.UnitTypeMinutes},
		"actions_linux_64_core_arm":   {Price: 0.16, Sku: "actions_linux_64_core_arm", FriendlyName: "Actions Linux ARM 64-core", Product: "actions", AzureMeterId: "23a9c13f-d79b-53af-9cd7-17c8431ff6ce", MeterType: models.PricingMeterDefault, FreeForPublicRepos: false, EffectiveAt: actionsRolloutEffectiveAt, UnitType: models.UnitTypeMinutes},
		"actions_windows_2_core_arm":  {Price: 0.01, Sku: "actions_windows_2_core_arm", FriendlyName: "Actions Windows ARM 2-core", Product: "actions", AzureMeterId: "f3a389b1-dae9-5f62-8aa3-b80e6d8e7691", MeterType: models.PricingMeterDefault, FreeForPublicRepos: false, EffectiveAt: actionsRolloutEffectiveAt, UnitType: models.UnitTypeMinutes},
		"actions_windows_4_core_arm":  {Price: 0.02, Sku: "actions_windows_4_core_arm", FriendlyName: "Actions Windows ARM 4-core", Product: "actions", AzureMeterId: "180cd407-6f6b-5cdf-9f02-5d567797b26a", MeterType: models.PricingMeterDefault, FreeForPublicRepos: false, EffectiveAt: actionsRolloutEffectiveAt, UnitType: models.UnitTypeMinutes},
		"actions_windows_8_core_arm":  {Price: 0.04, Sku: "actions_windows_8_core_arm", FriendlyName: "Actions Windows ARM 8-core", Product: "actions", AzureMeterId: "b9c794c5-86d0-576a-9e1b-40dfe8d4cfcf", MeterType: models.PricingMeterDefault, FreeForPublicRepos: false, EffectiveAt: actionsRolloutEffectiveAt, UnitType: models.UnitTypeMinutes},
		"actions_windows_16_core_arm": {Price: 0.08, Sku: "actions_windows_16_core_arm", FriendlyName: "Actions Windows ARM 16-core", Product: "actions", AzureMeterId: "dd5f6c09-d776-5cb2-ab5c-55b45d659902", MeterType: models.PricingMeterDefault, FreeForPublicRepos: false, EffectiveAt: actionsRolloutEffectiveAt, UnitType: models.UnitTypeMinutes},
		"actions_windows_32_core_arm": {Price: 0.16, Sku: "actions_windows_32_core_arm", FriendlyName: "Actions Windows ARM 32-core", Product: "actions", AzureMeterId: "a1883289-e411-5905-9a62-59829213a927", MeterType: models.PricingMeterDefault, FreeForPublicRepos: false, EffectiveAt: actionsRolloutEffectiveAt, UnitType: models.UnitTypeMinutes},
		"actions_windows_64_core_arm": {Price: 0.32, Sku: "actions_windows_64_core_arm", FriendlyName: "Actions Windows ARM 64-core", Product: "actions", AzureMeterId: "7f0c5a74-0231-5e8b-a175-3b3eb13f6235", MeterType: models.PricingMeterDefault, FreeForPublicRepos: false, EffectiveAt: actionsRolloutEffectiveAt, UnitType: models.UnitTypeMinutes},

		// Advanced Actions SKUs have same price and Azure Meter as default Actions SKUs of same environment for now
		"actions_linux_2_core_advanced":   {Price: 0.008, Sku: "actions_linux_2_core_advanced", FriendlyName: "Actions Linux Advanced 2-core", Product: "actions", AzureMeterId: "3dbfec75-284c-4c89-8c9c-0d395be81a0c", MeterType: models.PricingMeterDefault, FreeForPublicRepos: false, EffectiveAt: actionsRolloutEffectiveAt, UnitType: models.UnitTypeMinutes},
		"actions_windows_2_core_advanced": {Price: 0.016, Sku: "actions_windows_2_core_advanced", FriendlyName: "Actions Windows Advanced 2-core", Product: "actions", AzureMeterId: "cc383714-48b2-46c6-aa9d-62040318c9e0", MeterType: models.PricingMeterDefault, FreeForPublicRepos: false, EffectiveAt: actionsRolloutEffectiveAt, UnitType: models.UnitTypeMinutes},

		// 0.24 per GB per month / 744 normalized hours = ~0.00033602
		// its actually == 0.0003360215053763440 but that's a bonkers number of decimal places
		// so 0.00033602 = 0.249998880 which is pretty damn close and any rounding errors should be minimal.
		// todo: future us, what problems has this caused?
		"actions_storage": {Price: 0.00033602, Sku: "actions_storage", FriendlyName: "Actions storage", Product: "actions", AzureMeterId: "832bfa96-c7db-416b-aa5b-6ea89054d493", MeterType: models.PricingMeterPerHourUnitCharge, FreeForPublicRepos: true, EffectiveAt: actionsRolloutEffectiveAt, UnitType: models.UnitTypeGigabyteHours},

		// Codespaces
		"codespaces_compute_d16":      {Price: 1.44, Sku: "codespaces_compute_d16", FriendlyName: "Codespaces compute 16-core", Product: "codespaces", AzureMeterId: "9b239e02-c4d4-52e9-91a6-5fc18c11dc30", MeterType: models.PricingMeterDefault, FreeForPublicRepos: false, EffectiveAt: codespacesRolloutEffectiveAt, UnitType: models.UnitTypeHours},
		"codespaces_compute_d2":       {Price: 0.18, Sku: "codespaces_compute_d2", FriendlyName: "Codespaces compute 2-core", Product: "codespaces", AzureMeterId: "c97c82f0-c0b0-56ef-9fd5-cb83aceb645b", MeterType: models.PricingMeterDefault, FreeForPublicRepos: false, EffectiveAt: codespacesRolloutEffectiveAt, UnitType: models.UnitTypeHours},
		"codespaces_compute_d32":      {Price: 2.88, Sku: "codespaces_compute_d32", FriendlyName: "Codespaces compute 32-core", Product: "codespaces", AzureMeterId: "5140eabf-9548-5e38-97af-c1d6bc529231", MeterType: models.PricingMeterDefault, FreeForPublicRepos: false, EffectiveAt: codespacesRolloutEffectiveAt, UnitType: models.UnitTypeHours},
		"codespaces_compute_d4":       {Price: 0.36, Sku: "codespaces_compute_d4", FriendlyName: "Codespaces compute 4-core", Product: "codespaces", AzureMeterId: "a45db669-b74d-5822-af83-7eae14f67b53", MeterType: models.PricingMeterDefault, FreeForPublicRepos: false, EffectiveAt: codespacesRolloutEffectiveAt, UnitType: models.UnitTypeHours},
		"codespaces_compute_d8":       {Price: 0.72, Sku: "codespaces_compute_d8", FriendlyName: "Codespaces compute 8-core", Product: "codespaces", AzureMeterId: "74931794-ab82-5977-9700-c0f6196d2884", MeterType: models.PricingMeterDefault, FreeForPublicRepos: false, EffectiveAt: codespacesRolloutEffectiveAt, UnitType: models.UnitTypeHours},
		"codespaces_prebuild_storage": {Price: 0.07, Sku: "codespaces_prebuild_storage", FriendlyName: "Codespaces prebuild storage", Product: "codespaces", AzureMeterId: "4efa15aa-3748-5fca-8310-70a2f7b9e3f4", MeterType: models.PricingMeterDefault, FreeForPublicRepos: false, EffectiveAt: codespacesRolloutEffectiveAt, UnitType: models.UnitTypeGigabyteHours},
		"codespaces_storage":          {Price: 0.07, Sku: "codespaces_storage", FriendlyName: "Codespaces storage", Product: "codespaces", AzureMeterId: "4efa15aa-3748-5fca-8310-70a2f7b9e3f4", MeterType: models.PricingMeterDefault, FreeForPublicRepos: false, EffectiveAt: codespacesRolloutEffectiveAt, UnitType: models.UnitTypeGigabyteHours},

		// Disabled rollout
		"actions_self_hosted_linux":         {Price: 0.0, Sku: "actions_self_hosted_linux", FriendlyName: "Actions self hosted Linux", Product: "actions", AzureMeterId: "", MeterType: models.PricingMeterDefault, FreeForPublicRepos: false, EffectiveAt: disabledRolloutEffectiveAt, UnitType: models.UnitTypeMinutes},
		"actions_self_hosted_windows":       {Price: 0.0, Sku: "actions_self_hosted_windows", FriendlyName: "Actions self hosted Windows", Product: "actions", AzureMeterId: "", MeterType: models.PricingMeterDefault, FreeForPublicRepos: false, EffectiveAt: disabledRolloutEffectiveAt, UnitType: models.UnitTypeMinutes},
		"actions_self_hosted_macos":         {Price: 0.0, Sku: "actions_self_hosted_macos", FriendlyName: "Actions self hosted Macos", Product: "actions", AzureMeterId: "", MeterType: models.PricingMeterDefault, FreeForPublicRepos: false, EffectiveAt: disabledRolloutEffectiveAt, UnitType: models.UnitTypeMinutes},
		"actions_self_hosted_unknown":       {Price: 0.0, Sku: "actions_self_hosted_unknown", FriendlyName: "Actions self hosted unknown", Product: "actions", AzureMeterId: "", MeterType: models.PricingMeterDefault, FreeForPublicRepos: false, EffectiveAt: disabledRolloutEffectiveAt, UnitType: models.UnitTypeMinutes},
		"actions_beta_public_repository":    {Price: 0.0, Sku: "actions_beta_public_repository", FriendlyName: "Actions beta public repository", Product: "actions", AzureMeterId: "", MeterType: models.PricingMeterDefault, FreeForPublicRepos: false, EffectiveAt: disabledRolloutEffectiveAt, UnitType: models.UnitTypeMinutes},
		"actions_beta_classroom_repository": {Price: 0.0, Sku: "actions_beta_classroom_repository", FriendlyName: "Actions beta classroom repository", Product: "actions", AzureMeterId: "", MeterType: models.PricingMeterDefault, FreeForPublicRepos: false, EffectiveAt: disabledRolloutEffectiveAt, UnitType: models.UnitTypeMinutes},
		"actions_beta_self_hosted_runner":   {Price: 0.0, Sku: "actions_beta_self_hosted_runner", FriendlyName: "Actions beta self hosted runner", Product: "actions", AzureMeterId: "", MeterType: models.PricingMeterDefault, FreeForPublicRepos: false, EffectiveAt: disabledRolloutEffectiveAt, UnitType: models.UnitTypeMinutes},
		"actions_beta_macos_xl_runner":      {Price: 0.0, Sku: "actions_beta_macos_xl_runner", FriendlyName: "Actions beta macos xl runner", Product: "actions", AzureMeterId: "", MeterType: models.PricingMeterDefault, FreeForPublicRepos: false, EffectiveAt: disabledRolloutEffectiveAt, UnitType: models.UnitTypeMinutes},
		"actions_beta_custom_runner_azure":  {Price: 0.0, Sku: "actions_beta_custom_runner_azure", FriendlyName: "Actions beta custom runner azure", Product: "actions", AzureMeterId: "", MeterType: models.PricingMeterDefault, FreeForPublicRepos: false, EffectiveAt: disabledRolloutEffectiveAt, UnitType: models.UnitTypeMinutes},
		"actions_unknown":                   {Price: 0.0, Sku: "actions_unknown", FriendlyName: "Actions unknown", Product: "actions", AzureMeterId: "", MeterType: models.PricingMeterDefault, FreeForPublicRepos: false, EffectiveAt: disabledRolloutEffectiveAt, UnitType: models.UnitTypeMinutes},
		"copilot_for_business":              {Price: 19.0, Sku: "copilot_for_business", FriendlyName: "Copilot Business", Product: "copilot", AzureMeterId: "52b57f57-fb19-502a-8559-75de79d57df2", MeterType: models.PricingMeterDefault, FreeForPublicRepos: false, EffectiveAt: copilotForBusinessRolloutEffectiveAt, UnitType: models.UnitTypeUserMonths},
		"copilot_enterprise":                {Price: 39.0, Sku: "copilot_enterprise", FriendlyName: "Copilot Enterprise", Product: "copilot", AzureMeterId: "c199ed39-470c-57bb-b63e-a1e137de6db5", MeterType: models.PricingMeterDefault, FreeForPublicRepos: false, EffectiveAt: copilotEnterpriseRolloutEffectiveAt, UnitType: models.UnitTypeUserMonths},
		"copilot_standalone":                {Price: 19.0, Sku: "copilot_standalone", FriendlyName: "Copilot Business", Product: "copilot", AzureMeterId: "9e12e6dd-1e03-5b13-bf15-78ac65bdc9db", MeterType: models.PricingMeterDefault, FreeForPublicRepos: false, EffectiveAt: copilotStandaloneRolloutEffectiveAt, UnitType: models.UnitTypeUserMonths},
		"ghas_seats":                        {Price: 49.0, Sku: "ghas_seats", FriendlyName: "Advanced Security", Product: "ghas", AzureMeterId: "958aa327-8dca-57ec-879e-7b11eb971836", MeterType: models.PricingMeterDailyUnitCharge, FreeForPublicRepos: false, EffectiveAt: ghasRolloutEffectiveAt, UnitType: models.UnitTypeUserMonths},
		"ghec_seats":                        {Price: 21.0, Sku: "ghec_seats", FriendlyName: "GHEC seats", Product: "ghec", AzureMeterId: "bc843f27-e9da-5ee1-b628-2a60bd1a2a1f", MeterType: models.PricingMeterDailyUnitCharge, FreeForPublicRepos: false, EffectiveAt: ghecRolloutEffectiveAt, UnitType: models.UnitTypeUserMonths},
		// lfs storage calculated as 0.07 per GiB-month / 744 normalized hours = ~0.000094086
		"git_lfs_storage":   {Price: 0.000094086, Sku: "git_lfs_storage", FriendlyName: "Git LFS storage", Product: "git_lfs", AzureMeterId: "bf8ec46b-9900-5280-9cd4-45e65b3de557", MeterType: models.PricingMeterPerHourUnitCharge, FreeForPublicRepos: false, EffectiveAt: lfsStorageRolloutEffectiveAt, UnitType: models.UnitTypeGigabyteHours},
		"git_lfs_bandwidth": {Price: 0.0875, Sku: "git_lfs_bandwidth", FriendlyName: "Git LFS bandwidth", Product: "git_lfs", AzureMeterId: "aab878db-8160-55c2-95a9-33984456c160", MeterType: models.PricingMeterDefault, FreeForPublicRepos: false, EffectiveAt: lfsBandwidthRolloutEffectiveAt, UnitType: models.UnitTypeGigabytes},

		// Packages storage and bandwidth pricing
		// Storage price is the same as for `actions_storage`.
		"packages_storage":   {Price: 0.00033602, Sku: "packages_storage", FriendlyName: "Packages storage", Product: "packages", AzureMeterId: "832bfa96-c7db-416b-aa5b-6ea89054d493", MeterType: models.PricingMeterPerHourUnitCharge, FreeForPublicRepos: true, EffectiveAt: packagesRolloutEffectiveAt, UnitType: models.UnitTypeGigabyteHours},
		"packages_bandwidth": {Price: 0.5, Sku: "packages_bandwidth", FriendlyName: "Packages data transfer", Product: "packages", AzureMeterId: "1cfdf771-633e-4802-a7bb-edf1a81b2857", MeterType: models.PricingMeterDefault, FreeForPublicRepos: true, EffectiveAt: packagesRolloutEffectiveAt, UnitType: models.UnitTypeGigabytes},
	}
	return pricings
}
