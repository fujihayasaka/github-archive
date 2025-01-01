package models

import (
	"encoding/json"

	"github.com/github/billing-platform/internal/nano"
	"github.com/github/billing-platform/lib/twirp/proto"
	"github.com/github/billing-platform/lib/utils"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/pkg/errors"
)

type Item struct {
	Key
	*Amounts
	Pricing      *Pricing `json:",omitempty"`
	EntityDetail *EntityDetail
	SourceUri    string `json:",omitempty"`
	UsageAt      UsageTime
}

func (billingItem *Item) UnmarshalJSON(data []byte) error {
	var mi migratedItem
	if err := json.Unmarshal(data, &mi); err != nil {
		return errors.Wrap(err, "failed to unmarshal migrated item")
	}

	sku := mi.Sku
	product := mi.Product
	if mi.Pricing == nil {
		mi.Pricing = &Pricing{
			Sku:     sku,
			Product: product,
		}
	} else {
		if mi.Pricing.Sku == "" {
			mi.Pricing.Sku = sku
		}
		if mi.Pricing.Sku == "" {
			mi.Pricing.Sku = sku
		}
	}

	*billingItem = Item(*mi.UnmarshalAbleItem)
	return nil
}

func (billingItem *Item) GetAmounts() *Amounts {
	return billingItem.Amounts
}

func (billingItem *Item) GetCostCenterDetail() *CostCenterDetail {
	if billingItem.EntityDetail != nil {
		return billingItem.EntityDetail.CostCenterDetail
	}

	return nil
}

func (billingItem *Item) GetCustomerId() string {
	if billingItem.EntityDetail != nil {
		return billingItem.EntityDetail.GetCustomerId()
	}

	return ""
}

// GetLoggerFields returns a list of fields that should be present in a log line related to this item.
// The return value is typically going to be used with .WithFields() on the logger object.
// The intent is to pick item fields that will serve as good filters when searching the logs,
// i.e., when we want to debug what happened with usage of a particular customer.
// The intent is not to serialize the entire item into the log line. Fields like price
// should be only logged when needed.
func (billingItem *Item) GetLoggerFields() []kvp.Field {
	fields := billingItem.Key.GetLoggerFields()

	if billingItem.SourceUri != "" {
		fields = append(fields, kvp.String("source_uri", billingItem.SourceUri))
	}

	if billingItem.EntityDetail != nil && billingItem.EntityDetail.CustomerId != "" {
		fields = append(fields, kvp.String("customer_id", billingItem.EntityDetail.CustomerId))
	}

	sku := billingItem.GetSku()
	if sku != "" {
		fields = append(fields, kvp.String("sku", sku))
	}

	return fields
}

func (billingItem *Item) GetSku() string {
	if billingItem.Pricing != nil {
		return billingItem.Pricing.Sku
	}

	return ""
}

func (billingItem *Item) GetSkuName() string {
	if billingItem.Pricing != nil {
		return billingItem.Pricing.FriendlyName
	}

	return ""
}

func (billingItem *Item) GetProduct() string {
	if billingItem.Pricing != nil {
		return billingItem.Pricing.Product
	}

	return ""
}

func (billingItem *Item) GetOrgId() int64 {
	return billingItem.EntityDetail.OrganizationId
}

func (billingItem *Item) GetRepoId() int64 {
	return billingItem.EntityDetail.RepositoryId
}

func (billingItem *Item) GetUnitType() UnitType {
	if billingItem.Pricing != nil {
		return billingItem.Pricing.UnitType
	}
	return UnitTypeUnknown
}

func (billingItem *Item) GetMeterType() PricingMeterType {
	if billingItem.Pricing != nil {
		return billingItem.Pricing.MeterType
	}
	return PricingMeterDefault
}

func (billingItem *Item) GetPrice() int64 {
	if billingItem.Pricing != nil {
		return billingItem.Pricing.Price
	}
	return 0
}

func (billingItem *Item) GetAzureMeterId() string {
	if billingItem.Pricing != nil {
		return billingItem.Pricing.AzureMeterId
	}
	return ""
}

func (billingItem *Item) IsEnabledForEmission() bool {
	if billingItem.Pricing != nil && billingItem.Pricing.EffectiveAt > 0 {
		return billingItem.Pricing.EffectiveAt <= billingItem.UsageAt.Unix()
	}
	return false
}

func (billingItem *Item) AsYearlyItemWithPartitionKeyofType(from UsagePartitionType, to UsagePartitionType, fieldsToIgnore []string) *Item {
	bICopy := *billingItem
	bICopy.Id = billingItem.GetPartitionKey(Monthly, from)
	bICopy.PartitionKey = billingItem.GetPartitionKey(Yearly, to)
	if len(fieldsToIgnore) > 0 {
		bICopy.ignoreFields(fieldsToIgnore)
	}
	return &bICopy
}

func (billingItem *Item) AsMonthlyItemWithPartitionKeyofType(from UsagePartitionType, to UsagePartitionType, fieldsToIgnore []string) *Item {
	bICopy := *billingItem
	bICopy.Id = billingItem.GetPartitionKey(Daily, from)
	bICopy.PartitionKey = billingItem.GetPartitionKey(Monthly, to)
	if len(fieldsToIgnore) > 0 {
		bICopy.ignoreFields(fieldsToIgnore)
	}
	return &bICopy
}

func (billingItem *Item) AsDailyItemWithPartitionKeyofType(from UsagePartitionType, to UsagePartitionType, fieldsToIgnore []string) *Item {
	bICopy := *billingItem
	bICopy.Id = billingItem.GetPartitionKey(Hourly, from)
	bICopy.PartitionKey = billingItem.GetPartitionKey(Daily, to)
	if len(fieldsToIgnore) > 0 {
		bICopy.ignoreFields(fieldsToIgnore)
	}
	return &bICopy
}

func (billingItem *Item) AsMonthlyItemWithMonthlyPartitionKeyofType(from UsagePartitionType, to UsagePartitionType) *Item {
	bICopy := *billingItem
	bICopy.Id = billingItem.GetPartitionKey(Daily, from)
	bICopy.PartitionKey = billingItem.GetPartitionKey(Daily, to)

	return &bICopy
}

// AsItemWithEventPartitionKey Partition used to track all delta watermark events per Customer. We always aggregate at the Customer level given cost
// center assignment happens when we generate line items and emit usage back through the UsageHandler. This approach ensures
// that storage amounts are always correct even if a repository changes cost centers.
//
// Ex: "${customerId}:${sku}:events"
func (billingItem *Item) AsItemWithEventPartitionKey() *Item {
	bICopy := *billingItem
	bICopy.Id = bICopy.PartitionKey

	partitionDetail := &UsagePartitionDetail{
		UsageEntityId: bICopy.EntityDetail.CustomerId,
		UsageTime:     &bICopy.UsageAt,
		ActiveType:    Monthly,
		Sku:           bICopy.GetSku(),
	}

	bICopy.PartitionKey = partitionDetail.ToEventPartitionKey()

	amounts := *billingItem.Amounts
	fractionalHour := billingItem.UsageAt.BillableHoursForUsageDate(Hourly, &billingItem.UsageAt)
	nanoQuantity := nano.NewFromInt(billingItem.Amounts.Quantity)

	amounts.FractionalQuantity = nano.NewFromFloat(fractionalHour).Mul(nanoQuantity).Int64()
	bICopy.Amounts = &amounts
	return &bICopy
}

// AsItemWithEventPartitionKeyWithYearMonth Partition used to track all delta watermark events per Customer. We always aggregate at the Customer level given cost
// center assignment happens when we generate line items and emit usage back through the UsageHandler. This approach ensures
// that storage amounts are always correct even if a repository changes cost centers.
//
// Ex: "${customerId}:${sku}:events:2023:12"
func (billingItem *Item) AsItemWithEventPartitionKeyWithYearMonth() *Item {
	bICopy := *billingItem
	bICopy.Id = bICopy.PartitionKey

	partitionDetail := &UsagePartitionDetail{
		UsageEntityId: bICopy.EntityDetail.CustomerId,
		UsageTime:     &bICopy.UsageAt,
		ActiveType:    Monthly,
		Sku:           bICopy.GetSku(),
	}

	bICopy.PartitionKey = partitionDetail.ToEventPartitionKeyWithYearMonth()

	if billingItem.EntityDetail.CustomerId == "5018891" {
		return &Item{
			Key: Key{
				PartitionKey: partitionDetail.ToEventPartitionKeyWithYearMonth(),
				Id:           bICopy.Id,
			},
			UsageAt: bICopy.UsageAt,
		}
	}

	amounts := *billingItem.Amounts
	fractionalHour := billingItem.UsageAt.BillableHoursForUsageDate(Hourly, &billingItem.UsageAt)
	nanoQuantity := nano.NewFromInt(billingItem.Amounts.Quantity)

	amounts.FractionalQuantity = nano.NewFromFloat(fractionalHour).Mul(nanoQuantity).Int64()
	bICopy.Amounts = &amounts
	return &bICopy
}

// AsActualSubscriptionCountPartitionKey returns a copy of the item with the partition key set to the high watermark
// Ex: "${customerId}:watermark:${sku}"
// Stores the current value of the quantity for a high watermark sku
func (billingItem *Item) AsActualSubscriptionCountPartitionKey() *Item {
	bICopy := *billingItem
	copyID := &WatermarkID{
		KeyID:      bICopy.EntityDetail.CustomerId,
		ProductSKU: bICopy.GetSku(),
		OrgID:      bICopy.EntityDetail.OrganizationId,
		RepoID:     bICopy.EntityDetail.RepositoryId,
	}
	copyPK := &WatermarkPartitionKey{
		KeyID:      bICopy.EntityDetail.CustomerId,
		ProductSKU: bICopy.GetSku(),
	}
	bICopy.Id = copyID.String()
	bICopy.PartitionKey = copyPK.String()

	// Copy amounts so if another function updates the quantity
	// before we save to the DB, this won't be impacted
	amountsCopy := *bICopy.Amounts
	bICopy.Amounts = &amountsCopy
	return &bICopy
}

// AsItemWithHighWatermarkPartitionKey returns a copy of the billing item with the partition key set to the high watermark
// Ex: "${customerId}:highWatermark:${sku}:${year}:${month}"
// Stores the high watermark value for a certain month
func (billingItem *Item) AsItemWithHighWatermarkPartitionKey() *Item {
	bICopy := *billingItem
	bICopy.Key = *ToSubscriptionPartitionKeyForGivenMonthHighWaterMark(bICopy.EntityDetail.CustomerId, bICopy.GetSku(), bICopy.UsageAt)
	return &bICopy
}

func (billingItem *Item) AsSubscribedItem() *SubscribedItem {
	return NewSubscribedItemFromItem(billingItem)
}

func (billingItem *Item) IsRollOverFromPreviousMonth() bool {
	return billingItem.SourceUri == RollOverFromPreviousMonth
}

func (billingItem *Item) GetPartitionKey(activeType ActiveType, upt UsagePartitionType) string {
	return GetPartitionKey(billingItem, upt, activeType)
}

func (billingItem *Item) ToBillingItemWithNoSkuPartitionKeyPart(t ActiveType) *Item {
	bICopy := *billingItem
	bICopy.PartitionKey = GetPartitionKey(billingItem, ByCustomer, t)
	return &bICopy
}

func (billingItem *Item) ToBillingItemWithOrgPartitionPart(t ActiveType) *Item {
	biCopy := *billingItem
	biCopy.PartitionKey = GetPartitionKey(billingItem, ByCustomerOrg, t)
	return &biCopy
}

func (billingItem *Item) ToBillingItemWithOrgRepoPartitionPart(t ActiveType) *Item {
	bICopy := *billingItem
	bICopy.PartitionKey = GetPartitionKey(billingItem, ByCustomerOrgRepo, t)
	return &bICopy
}

func (billingItem *Item) ToBillingItemWithProductPartitionKeyPart(t ActiveType) *Item {
	bICopy := *billingItem
	bICopy.PartitionKey = GetPartitionKey(billingItem, ByCustomerProduct, t)
	return &bICopy
}

func (billingItem *Item) ToBillingItemWithRepoSkuPartitionKeyPart(t ActiveType) *Item {
	bICopy := *billingItem
	bICopy.PartitionKey = GetPartitionKey(billingItem, ByCustomerRepoByProductSku, t)
	return &bICopy
}

func (billingItem *Item) ToBillingItemWithOrgSkuPartitionKeyPart(t ActiveType) *Item {
	bICopy := *billingItem
	bICopy.PartitionKey = GetPartitionKey(billingItem, ByCustomerOrgByProductSku, t)
	return &bICopy
}

func (billingItem *Item) ToBillingItemWithoutCustomerPartitionKeyPart(t ActiveType) *Item {
	bICopy := *billingItem
	bICopy.PartitionKey = GetPartitionKey(billingItem, BySku, t)
	return &bICopy
}

func (billingItem *Item) ToProto() *proto.BillingItem {
	customerId := billingItem.GetCustomerId()
	quantity := float64(0)
	fullQuantity := float64(0)
	billedAmount := float64(0)
	appliedCostPerQuantity := float64(0)
	if billingItem.Amounts != nil {
		amounts := billingItem.Amounts.ToDecimal()
		quantity = amounts.Quantity
		fullQuantity = amounts.FullQuantity
		billedAmount = amounts.BilledAmount
		appliedCostPerQuantity = amounts.AppliedCostPerQuantity
	}

	var selfReference *proto.Key
	if billingItem.Id != "" || billingItem.PartitionKey != "" {
		selfReference = &proto.Key{
			PartitionKey: billingItem.PartitionKey,
			Id:           billingItem.Id,
		}
	}

	repoId := billingItem.EntityDetail.RepositoryId
	orgId := billingItem.EntityDetail.OrganizationId

	return &proto.BillingItem{
		UsageEntityId:          customerId,
		Sku:                    billingItem.GetSku(),
		Product:                billingItem.GetProduct(),
		Quantity:               quantity,
		FullQuantity:           fullQuantity,
		BilledAmount:           billedAmount,
		AppliedCostPerQuantity: appliedCostPerQuantity,
		UsageAt:                billingItem.UsageAt.UnixMilli(),
		SelfReference:          selfReference,
		FriendlySkuName:        billingItem.GetSkuName(),
		RepoId:                 repoId,
		OrgId:                  orgId,
		UnitType:               billingItem.GetUnitType().ToProto(),
	}
}

func (billingItem *Item) ToNetUsageItemProto(discountItem *DiscountItem, calculateLicensedFields bool) *proto.NetUsageItem {
	customerId := billingItem.GetCustomerId()
	quantity := float64(0)
	fullQuantity := float64(0)
	grossAmount := float64(0)
	discountAmount := float64(0)
	netAmount := float64(0)
	appliedCostPerQuantity := float64(0)
	if billingItem.Amounts != nil {
		amounts := billingItem.Amounts.ToDecimal()
		quantity = amounts.Quantity
		fullQuantity = amounts.FullQuantity
		grossAmount = amounts.BilledAmount
		appliedCostPerQuantity = amounts.AppliedCostPerQuantity
	}

	if discountItem != nil {
		discountAmount = ToDecimalAmount(discountItem.DiscountAmount)
	}

	netAmount = grossAmount - discountAmount

	var selfReference *proto.Key
	if billingItem.Id != "" || billingItem.PartitionKey != "" {
		selfReference = &proto.Key{
			PartitionKey: billingItem.PartitionKey,
			Id:           billingItem.Id,
		}
	}

	repoId := billingItem.EntityDetail.RepositoryId
	orgId := billingItem.EntityDetail.OrganizationId

	netUsageItem := &proto.NetUsageItem{
		UsageEntityId:          customerId,
		Sku:                    billingItem.GetSku(),
		Product:                billingItem.GetProduct(),
		Quantity:               quantity,
		FullQuantity:           fullQuantity,
		GrossAmount:            grossAmount,
		DiscountAmount:         discountAmount,
		NetAmount:              netAmount,
		AppliedCostPerQuantity: appliedCostPerQuantity,
		UsageAt:                billingItem.UsageAt.UnixMilli(),
		SelfReference:          selfReference,
		FriendlySkuName:        billingItem.GetSkuName(),
		RepoId:                 repoId,
		OrgId:                  orgId,
		UnitType:               billingItem.GetUnitType().ToProto(),
	}

	if calculateLicensedFields {
		netUsageItem.DailyLicenseCost = billingItem.getDailyLicenseCost()
		netUsageItem.DailyLicenseQuantity = billingItem.getDailyLicenseQuantity()
	}
	return netUsageItem
}

type UsageItem struct {
	UsageEntityId   string
	Sku             string
	Product         string
	UsageAt         int64
	GrossAmount     float64
	DiscountAmount  float64
	NetAmount       float64
	FriendlySkuName string
	RepoId          int64
	OrgId           int64
}

func (billingItem *Item) ToUsageItem(discountItem *DiscountItem) *UsageItem {
	customerId := billingItem.GetCustomerId()
	grossAmount := float64(0)
	discountAmount := float64(0)
	netAmount := float64(0)
	if billingItem.Amounts != nil {
		amounts := billingItem.Amounts.ToDecimal()
		grossAmount = amounts.BilledAmount
		netAmount = grossAmount
	}

	if discountItem != nil {
		discountAmount = ToDecimalAmount(discountItem.DiscountAmount)
		netAmount = grossAmount - discountAmount
	}

	repoId := billingItem.EntityDetail.RepositoryId
	orgId := billingItem.EntityDetail.OrganizationId

	return &UsageItem{
		UsageEntityId:   customerId,
		Sku:             billingItem.GetSku(),
		Product:         billingItem.GetProduct(),
		GrossAmount:     grossAmount,
		DiscountAmount:  discountAmount,
		NetAmount:       netAmount,
		UsageAt:         billingItem.UsageAt.UnixMilli(),
		FriendlySkuName: billingItem.GetSkuName(),
		RepoId:          repoId,
		OrgId:           orgId,
	}
}

func (billingItem *Item) ToReportUsageProto(discountAmount float64, costCenterNames map[string]string) *proto.ReportItem {
	quantity := float64(0)
	billedAmount := float64(0)
	pricePerUnit := float64(0)
	repoId := billingItem.EntityDetail.RepositoryId
	orgId := billingItem.EntityDetail.OrganizationId

	if billingItem.Amounts != nil {
		amounts := billingItem.Amounts.ToDecimal()
		quantity = amounts.Quantity
		billedAmount = amounts.BilledAmount
		pricePerUnit = amounts.AppliedCostPerQuantity
	}

	return &proto.ReportItem{
		UsageDate:      billingItem.UsageAt.Unix(),
		Product:        billingItem.GetProduct(),
		Sku:            billingItem.GetSkuName(),
		Quantity:       quantity,
		UnitTypeString: billingItem.GetUnitType().ToProto().String(),
		PricePerUnit:   pricePerUnit,
		GrossAmount:    billedAmount,
		DiscountAmount: discountAmount,
		NetAmount:      billedAmount - discountAmount,
		OrgID:          orgId,
		RepoID:         repoId,
		CostCenterName: costCenterNames[billingItem.GetCostCenterDetail().CostCenterUUID],
	}
}

func (billingItem *Item) ToRepoUsageProto() *proto.RepoUsage {
	quantity := float64(0)
	billedAmount := float64(0)
	repoId := billingItem.EntityDetail.RepositoryId
	orgId := billingItem.EntityDetail.OrganizationId
	if billingItem.Amounts != nil {
		amounts := billingItem.Amounts.ToDecimal()
		quantity = amounts.Quantity
		billedAmount = amounts.BilledAmount
	}

	var selfReference *proto.Key
	if billingItem.Id != "" || billingItem.PartitionKey != "" {
		selfReference = &proto.Key{
			PartitionKey: billingItem.PartitionKey,
			Id:           billingItem.Id,
		}
	}

	return &proto.RepoUsage{
		RepoId:        repoId,
		OrgId:         orgId,
		Quantity:      quantity,
		BilledAmount:  billedAmount,
		UsageAt:       billingItem.UsageAt.UnixMilli(),
		SelfReference: selfReference,
	}
}

func (billingItem *UsageItem) ToTopOrgRepoUsage() *proto.TopOrgRepoUsage {
	return &proto.TopOrgRepoUsage{
		RepoId:         billingItem.RepoId,
		OrgId:          billingItem.OrgId,
		BilledAmount:   billingItem.GrossAmount,
		NetAmount:      billingItem.NetAmount,
		DiscountAmount: billingItem.DiscountAmount,
		UsageAt:        billingItem.UsageAt,
	}
}

func (billingItem *UsageItem) ToOtherUsage() *proto.BillingItem {
	return &proto.BillingItem{
		BilledAmount:   billingItem.GrossAmount,
		NetAmount:      billingItem.NetAmount,
		DiscountAmount: billingItem.DiscountAmount,
		UsageAt:        billingItem.UsageAt,
	}
}

func (billingItem *UsageItem) IncrementAmounts(incrementItem *UsageItem) {
	billingItem.GrossAmount += incrementItem.GrossAmount
	billingItem.DiscountAmount += incrementItem.DiscountAmount
	billingItem.NetAmount += incrementItem.NetAmount
}

func (billingItem *UsageItem) DecrementAmounts(incrementItem *UsageItem) {
	billingItem.GrossAmount -= incrementItem.GrossAmount
	billingItem.DiscountAmount -= incrementItem.DiscountAmount
	billingItem.NetAmount -= incrementItem.NetAmount
}

// Returns true for line items that are generated from events
func (billingItem *Item) IsProcessed() bool {
	return billingItem.SourceUri == InternallyProcessedEvent
}

func (billingItem *Item) IsCostCenterProxy() bool {
	return billingItem.EntityDetail.IsCostCenterProxy()
}

func (billingItem *Item) ConvertToDailyEmission() *Item {
	bICopy := *billingItem

	// Days in month as a nano amount
	daysInMonth := int64(billingItem.UsageAt.BillableDaysInMonth()) * nano.NanoDivisor
	entityQuantity := nano.NewFromInt(billingItem.Quantity).Div(nano.NewFromInt(daysInMonth))

	bICopy.Quantity = entityQuantity.Int64()
	bICopy.Amounts.Quantity = entityQuantity.Int64()

	return &bICopy
}

type FieldSetter func(*Item)

var fieldSetters = map[string]FieldSetter{
	"Amounts":      func(b *Item) { b.Amounts = nil },
	"Pricing":      func(b *Item) { b.Pricing = nil },
	"EntityDetail": func(b *Item) { b.EntityDetail = nil },
	"SourceUri":    func(b *Item) { b.SourceUri = "" },
	// Since EntityDetail is a pointer, make a copy of it to ensure we don't modify the original item's EntityDetail
	"ActorId": func(b *Item) {
		copiedEntityDetail := *b.EntityDetail
		copiedEntityDetail.ActorId = 0
		b.EntityDetail = &copiedEntityDetail
	},
	"OrganizationId": func(b *Item) {
		copiedEntityDetail := *b.EntityDetail
		copiedEntityDetail.OrganizationId = 0
		b.EntityDetail = &copiedEntityDetail
	},
	"RepositoryId": func(b *Item) {
		copiedEntityDetail := *b.EntityDetail
		copiedEntityDetail.RepositoryId = 0
		b.EntityDetail = &copiedEntityDetail
	},
}

func (billingItem *Item) ignoreFields(fieldsToIgnore []string) {
	for _, field := range fieldsToIgnore {
		if setter, ok := fieldSetters[field]; ok {
			setter(billingItem)
		}
	}
}

// returns the number of days in the month of the usage date for licensed SKUs with daily emission,
// and returns 0 and false for all other skus
func (billingItem *Item) getDaysForLicensedSkuWithDailyEmission() (int, bool) {
	if billingItem.Pricing == nil || !billingItem.Pricing.IsLicensedSkuWithDailyEmission() {
		return 0, false
	}

	year, month, _ := billingItem.UsageAt.Date()
	daysInMonth := utils.DaysInMonth(month, year)
	return daysInMonth, true
}

// only relevant for licensed skus with daily emissions, so we return 0 for all other cases
func (billingItem *Item) getDailyLicenseCost() float64 {
	if days, ok := billingItem.getDaysForLicensedSkuWithDailyEmission(); ok {
		return ToDecimalAmount(billingItem.Amounts.AppliedCostPerQuantity / int64(days))
	}
	return 0
}

// only relevant for licensed skus with daily emissions, so we return 0 for all other cases
func (billingItem *Item) getDailyLicenseQuantity() float64 {
	if days, ok := billingItem.getDaysForLicensedSkuWithDailyEmission(); ok {
		return billingItem.Amounts.ToDecimal().Quantity * float64(days)
	}
	return 0
}
