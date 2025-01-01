package models

import (
	"fmt"
	"testing"
	"time"

	"github.com/github/billing-platform/internal/nano"
	"github.com/github/billing-platform/lib/twirp/proto"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/onsi/gomega"
)

func Test_Item_GetLoggerFields(t *testing.T) {
	g := gomega.NewGomegaWithT(t)

	item := &Item{}
	fields := item.GetLoggerFields()
	g.Expect(fields).To(gomega.Equal([]kvp.Field{
		kvp.String("db.cosmosdb.partition_key", ""),
		kvp.String("db.cosmosdb.document_id", ""),
	}))

	item.PartitionKey = "pk"
	item.SourceUri = "gid://git-hub/CheckRun/123"
	item.EntityDetail = &EntityDetail{
		CustomerId: "123",
	}
	item.Pricing = &Pricing{
		Sku: "sku-x",
	}

	fields = item.GetLoggerFields()
	g.Expect(fields).To(gomega.Equal([]kvp.Field{
		kvp.String("db.cosmosdb.partition_key", "pk"),
		kvp.String("db.cosmosdb.document_id", ""),
		kvp.String("source_uri", "gid://git-hub/CheckRun/123"),
		kvp.String("customer_id", "123"),
		kvp.String("sku", "sku-x"),
	}))
}

func Test_Item_ToProto(t *testing.T) {
	item := createItemStub("4", 5, 6, 7)

	billingItem := item.ToProto()

	expectedProduct := item.GetProduct()
	expectedSku := item.GetSku()
	if billingItem.Product != expectedProduct {
		t.Errorf("Expected product to be %s, got %s", expectedProduct, billingItem.Product)
	}
	if billingItem.GetSku() != expectedSku {
		t.Errorf("Expected sku to be %s, got %s", expectedSku, billingItem.GetSku())
	}
	expectedBilledAmount := 6.0
	if billingItem.BilledAmount != expectedBilledAmount {
		t.Errorf("Expected billed amount to be %f, got %f", expectedBilledAmount, billingItem.BilledAmount)
	}
	expectedQuantity := 2.0
	if billingItem.Quantity != expectedQuantity {
		t.Errorf("Expected quantity to be %f, got %f", expectedQuantity, billingItem.Quantity)
	}
	expectedFullQuantity := 3.0
	if billingItem.FullQuantity != expectedFullQuantity {
		t.Errorf("Expected quantity to be %f, got %f", expectedFullQuantity, billingItem.FullQuantity)
	}
	if billingItem.UsageAt != item.UsageAt.UnixMilli() {
		t.Errorf("Expected quantity to be %v, got %v", item.UsageAt, billingItem.UsageAt)
	}

	customerID := item.GetCustomerId()
	if billingItem.UsageEntityId != customerID {
		t.Errorf("Expected usage entity id to be %s, got %s", customerID, billingItem.UsageEntityId)
	}
	if billingItem.SelfReference == nil {
		t.Fatal("Expected self reference to be set")
	}
	if billingItem.SelfReference.Id != item.Id {
		t.Errorf("Expected self reference id to be %s, got %s", item.Id, billingItem.SelfReference.Id)
	}
	if billingItem.SelfReference.PartitionKey != item.PartitionKey {
		t.Errorf("Expected self reference partition key to be %s, got %s", item.PartitionKey, billingItem.SelfReference.PartitionKey)
	}
}

func Test_Item_ToProto_Safe(t *testing.T) {
	item := createItemStub("4", 5, 6, 7)

	billingItem := item.ToProto()

	expectedProuct := item.GetProduct()
	expectedSku := item.GetSku()

	if billingItem.Product != expectedProuct {
		t.Errorf("Expected product to be %s, got %s", expectedProuct, billingItem.Product)
	}
	if billingItem.GetSku() != expectedSku {
		t.Errorf("Expected sku to be %s, got %s", expectedSku, billingItem.GetSku())
	}

	if billingItem.UnitType != proto.UnitType_Minutes {
		t.Errorf("Expected unit type to be %s, got %s", proto.UnitType_Minutes, billingItem.UnitType)
	}
}

func Test_Item_ConvertToDailyEmission(t *testing.T) {
	item := &Item{
		Pricing: &Pricing{
			Product: "product",
			Sku:     "sku",
		},
		EntityDetail: &EntityDetail{
			OrganizationId: 5,
			RepositoryId:   6,
		},
		Amounts: &Amounts{
			BilledAmount:           1,
			Quantity:               2,
			AppliedCostPerQuantity: 3,
		},
	}

	billingItem := item.ConvertToDailyEmission()
	daysInMonth := int64(billingItem.UsageAt.BillableDaysInMonth()) * nano.NanoDivisor

	expectedQuantity := 2.0 / daysInMonth

	if billingItem.Amounts.Quantity != expectedQuantity {
		t.Errorf("Expected quantity to be %d, got %d", expectedQuantity, billingItem.Amounts.Quantity)
	}
}

func Test_Item_AsItemWithEventPartitionKey(t *testing.T) {
	item := createItemStub("4", 5, 6, 7)

	billingItem := item.AsItemWithEventPartitionKey()
	expectedPK := fmt.Sprintf("%s:%s:events", item.EntityDetail.CustomerId, item.GetSku())

	if billingItem.PartitionKey != expectedPK {
		t.Errorf("Expected customer ID to be %s, got %s", expectedPK, billingItem.PartitionKey)
	}
}

func Test_Item_AsItemWithEventPartitionKeyWithYearMonth(t *testing.T) {
	item := createItemStub("123", 5, 6, 7)

	billingItem := item.AsItemWithEventPartitionKeyWithYearMonth()
	expectedPK := fmt.Sprintf("%s:%s:events:%d:%d", item.EntityDetail.CustomerId, item.GetSku(), item.UsageAt.Year(), item.UsageAt.Month())

	if billingItem.PartitionKey != expectedPK {
		t.Errorf("Expected customer ID to be %s, got %s", expectedPK, billingItem.PartitionKey)
	}
}

func Test_Item_AsDailyItemWithPartitionKeyofType(t *testing.T) {
	usageAt := *NewUsageTimeFromTime(time.Now())
	customerId := "123"
	orgId := int64(5)
	actorId := int64(7)
	repoId := int64(6)

	item := createItemStub(customerId, orgId, repoId, actorId)
	pricingCopy := *item.Pricing

	// With a fieldToIgnore provided for the ByCustomerOrgRepo partition
	year, month, day, hour := usageAt.Year(), int(usageAt.Month()), usageAt.Day(), usageAt.Hour()
	billingItem := item.AsDailyItemWithPartitionKeyofType(ByCustomerRepo, ByCustomerOrgRepo, []string{"Pricing"})
	expectedPk := fmt.Sprintf("%s:%d:%d:%d:byOrgAndRepo", item.EntityDetail.CustomerId, year, month, day)
	expectedId := fmt.Sprintf("%s:repo:%d:%d:%d:%d:%d", item.EntityDetail.CustomerId, item.EntityDetail.RepositoryId, year, month, day, hour)

	checkBillingItemKey(t, billingItem, expectedPk, expectedId)
	assertZeroValues(t, billingItem, []string{"Pricing"})

	// Without a fieldToIgnore provided for the ByCustomerOrgRepo partition
	billingItem = item.AsDailyItemWithPartitionKeyofType(ByCustomerRepo, ByCustomerOrgRepo, nil)

	expectedPricing := item.Pricing

	checkBillingItemKey(t, billingItem, expectedPk, expectedId)

	if billingItem.Pricing != expectedPricing {
		t.Errorf("Expected pricing to be %v, got %v", expectedPricing, billingItem.Pricing)
	}

	// With a fieldToIgnore provided for ByCustomerOrg partition
	billingItem = item.AsDailyItemWithPartitionKeyofType(ByCustomerRepo, ByCustomerOrg, []string{"Pricing", "SourceUri", "ActorId"})
	expectedPk = fmt.Sprintf("%s:org:%d:%d:%d:%d", item.EntityDetail.CustomerId, orgId, year, month, day)
	expectedId = fmt.Sprintf("%s:repo:%d:%d:%d:%d:%d", item.EntityDetail.CustomerId, item.EntityDetail.RepositoryId, year, month, day, hour)

	checkBillingItemKey(t, billingItem, expectedPk, expectedId)
	assertZeroValues(t, billingItem, []string{"Pricing", "SourceUri", "ActorId"})

	// ensure item is not changed by updates to the billingItem
	checkOriginalItem(t, actorId, item.EntityDetail.ActorId, "ActorId")
	checkOriginalItem(t, "sourceUri", item.SourceUri, "SourceUri")
	checkOriginalItem(t, pricingCopy.Product, item.GetProduct(), "Product")
	checkOriginalItem(t, pricingCopy.GetSku(), item.GetSku(), "Sku")

	// With fieldToIgnore provided for ByCustomerSku partition
	billingItem = item.AsDailyItemWithPartitionKeyofType(ByCustomerSku, ByCustomerSku, []string{"ActorId", "OrganizationId", "RepositoryId", "SourceUri"})
	expectedPk = fmt.Sprintf("%s:%s:%d:%d:%d", item.EntityDetail.CustomerId, item.GetSku(), year, month, day)
	expectedId = fmt.Sprintf("%s:%s:%d:%d:%d:%d", item.EntityDetail.CustomerId, item.GetSku(), year, month, day, hour)

	checkBillingItemKey(t, billingItem, expectedPk, expectedId)
	assertZeroValues(t, billingItem, []string{"ActorId", "OrganizationId", "RepositoryId", "SourceUri"})

	// With fieldToIgnore provided for ByCustomerProduct partition
	billingItem = item.AsDailyItemWithPartitionKeyofType(ByCustomerSku, ByCustomerProduct, []string{"ActorId", "OrganizationId", "RepositoryId", "SourceUri"})
	expectedPk = fmt.Sprintf("%s:%s:%d:%d:%d", item.EntityDetail.CustomerId, item.GetProduct(), year, month, day)
	expectedId = fmt.Sprintf("%s:%s:%d:%d:%d:%d", item.EntityDetail.CustomerId, item.GetSku(), year, month, day, hour)

	checkBillingItemKey(t, billingItem, expectedPk, expectedId)
	assertZeroValues(t, billingItem, []string{"ActorId", "OrganizationId", "RepositoryId", "SourceUri"})
	// ensure item is not changed by updates to the billingItem
	checkOriginalItem(t, actorId, item.EntityDetail.ActorId, "ActorId")
	checkOriginalItem(t, "sourceUri", item.SourceUri, "SourceUri")
	checkOriginalItem(t, orgId, item.EntityDetail.OrganizationId, "OrganizationId")
	checkOriginalItem(t, repoId, item.EntityDetail.RepositoryId, "RepositoryId")

	// With fieldToIgnore provided for ByCustomer partition
	billingItem = item.AsDailyItemWithPartitionKeyofType(ByCustomerSku, ByCustomer, []string{"ActorId", "OrganizationId", "RepositoryId", "SourceUri"})
	expectedPk = fmt.Sprintf("%s:%d:%d:%d", item.EntityDetail.CustomerId, year, month, day)
	expectedId = fmt.Sprintf("%s:%s:%d:%d:%d:%d", item.EntityDetail.CustomerId, item.GetSku(), year, month, day, hour)

	checkBillingItemKey(t, billingItem, expectedPk, expectedId)
	assertZeroValues(t, billingItem, []string{"ActorId", "OrganizationId", "RepositoryId", "SourceUri"})

	// ensure original item is not changed by updates to the billingItem
	checkOriginalItem(t, actorId, item.EntityDetail.ActorId, "ActorId")
	checkOriginalItem(t, "sourceUri", item.SourceUri, "SourceUri")
	checkOriginalItem(t, orgId, item.EntityDetail.OrganizationId, "OrganizationId")
	checkOriginalItem(t, repoId, item.EntityDetail.RepositoryId, "RepositoryId")
}

func Test_Item_AsMonthlyItemWithPartitionKeyofType(t *testing.T) {
	usageAt := *NewUsageTimeFromTime(time.Now())
	customerId := "123"
	orgId := int64(5)
	repoId := int64(6)
	actorId := int64(7)

	item := createItemStub(customerId, orgId, repoId, actorId)
	pricingCopy := *item.Pricing

	// With a fieldToIgnore provided for the ByCustomerOrgRepo partition
	year, month, day := usageAt.Year(), int(usageAt.Month()), usageAt.Day()
	billingItem := item.AsMonthlyItemWithPartitionKeyofType(ByCustomerRepo, ByCustomerOrgRepo, []string{"Pricing", "ActorId"})
	expectedPk := fmt.Sprintf("%s:%d:%d:byOrgAndRepo", item.EntityDetail.CustomerId, year, month)
	expectedId := fmt.Sprintf("%s:repo:%d:%d:%d:%d", item.EntityDetail.CustomerId, item.EntityDetail.RepositoryId, year, month, day)

	checkBillingItemKey(t, billingItem, expectedPk, expectedId)
	assertZeroValues(t, billingItem, []string{"Pricing", "ActorId"})

	// ensure the original item is not changed by the changes to the billingItem
	checkOriginalItem(t, actorId, item.EntityDetail.ActorId, "ActorId")
	checkOriginalItem(t, pricingCopy.Product, item.GetProduct(), "Product")
	checkOriginalItem(t, pricingCopy.GetSku(), item.GetSku(), "Sku")

	// Without a fieldToIgnore provided for the ByCustomerOrgRepo partition
	billingItem = item.AsMonthlyItemWithPartitionKeyofType(ByCustomerRepo, ByCustomerOrgRepo, nil)

	expectedPricing := item.Pricing

	checkBillingItemKey(t, billingItem, expectedPk, expectedId)

	if billingItem.Pricing != expectedPricing {
		t.Errorf("Expected pricing to be %v, got %v", expectedPricing, billingItem.Pricing)
	}

	// With a fieldToIgnore provided for the ByCustomerOrg partition
	billingItem = item.AsMonthlyItemWithPartitionKeyofType(ByCustomerRepo, ByCustomerOrg, []string{"Pricing", "ActorId", "SourceUri"})
	expectedPk = fmt.Sprintf("%s:org:%d:%d:%d", item.EntityDetail.CustomerId, orgId, year, month)
	expectedId = fmt.Sprintf("%s:repo:%d:%d:%d:%d", item.EntityDetail.CustomerId, item.EntityDetail.RepositoryId, year, month, day)

	checkBillingItemKey(t, billingItem, expectedPk, expectedId)
	assertZeroValues(t, billingItem, []string{"Pricing", "ActorId", "SourceUri"})

	// With a fieldToIgnore provided for the ByCustomerRepo partition
	billingItem = item.AsMonthlyItemWithPartitionKeyofType(ByCustomerRepo, ByCustomerRepo, []string{"Pricing", "ActorId", "SourceUri"})
	expectedPk = fmt.Sprintf("%s:repo:%d:%d:%d", item.EntityDetail.CustomerId, item.EntityDetail.RepositoryId, year, month)
	expectedId = fmt.Sprintf("%s:repo:%d:%d:%d:%d", item.EntityDetail.CustomerId, item.EntityDetail.RepositoryId, year, month, day)

	checkBillingItemKey(t, billingItem, expectedPk, expectedId)
	assertZeroValues(t, billingItem, []string{"Pricing", "ActorId", "SourceUri"})

	// With fieldToIgnore provided for ByCustomerSku partition
	billingItem = item.AsMonthlyItemWithPartitionKeyofType(ByCustomerSku, ByCustomerSku, []string{"ActorId", "OrganizationId", "RepositoryId", "SourceUri"})
	expectedPk = fmt.Sprintf("%s:%s:%d:%d", item.EntityDetail.CustomerId, item.GetSku(), year, month)
	expectedId = fmt.Sprintf("%s:%s:%d:%d:%d", item.EntityDetail.CustomerId, item.GetSku(), year, month, day)

	checkBillingItemKey(t, billingItem, expectedPk, expectedId)
	assertZeroValues(t, billingItem, []string{"ActorId", "OrganizationId", "RepositoryId", "SourceUri"})

	// ensure the original item is not changed by the changes to the billingItem
	checkOriginalItem(t, actorId, item.EntityDetail.ActorId, "ActorId")
	checkOriginalItem(t, "sourceUri", item.SourceUri, "SourceUri")
	checkOriginalItem(t, orgId, item.EntityDetail.OrganizationId, "OrganizationId")
	checkOriginalItem(t, repoId, item.EntityDetail.RepositoryId, "RepositoryId")

	if item.EntityDetail.ActorId != actorId {
		t.Errorf("Expected ActorId to retain original value of %d, but got %d", actorId, item.EntityDetail.ActorId)
	}
	if item.EntityDetail.OrganizationId != orgId {
		t.Errorf("Expected OrganizationId to retain original value of %d, but got %d", orgId, item.EntityDetail.OrganizationId)
	}
	if item.EntityDetail.RepositoryId != repoId {
		t.Errorf("Expected RepositoryId to retain original value of 6, but got %d", item.EntityDetail.RepositoryId)
	}
	if item.SourceUri != "sourceUri" {
		t.Errorf("Expected SourceUri to retain original value of 'sourceUri', but got %s", item.SourceUri)
	}

	// With a fieldToIgnore provided for the ByCustomer partition
	billingItem = item.AsMonthlyItemWithPartitionKeyofType(ByCustomerSku, ByCustomer, []string{"ActorId", "OrganizationId", "RepositoryId", "SourceUri"})
	expectedPk = fmt.Sprintf("%s:%d:%d", item.EntityDetail.CustomerId, year, month)
	expectedId = fmt.Sprintf("%s:%s:%d:%d:%d", item.EntityDetail.CustomerId, item.GetSku(), year, month, day)
	checkBillingItemKey(t, billingItem, expectedPk, expectedId)
	assertZeroValues(t, billingItem, []string{"ActorId", "OrganizationId", "RepositoryId", "SourceUri"})

	// ensure the original item is not changed by the changes to the billingItem
	checkOriginalItem(t, actorId, item.EntityDetail.ActorId, "ActorId")
	checkOriginalItem(t, "sourceUri", item.SourceUri, "SourceUri")
	checkOriginalItem(t, orgId, item.EntityDetail.OrganizationId, "OrganizationId")
	checkOriginalItem(t, repoId, item.EntityDetail.RepositoryId, "RepositoryId")

	// With fieldToIgnore provided for ByCustomerProduct partition
	billingItem = item.AsMonthlyItemWithPartitionKeyofType(ByCustomerSku, ByCustomerProduct, []string{"ActorId", "OrganizationId", "RepositoryId", "SourceUri"})
	expectedPk = fmt.Sprintf("%s:%s:%d:%d", item.EntityDetail.CustomerId, item.GetProduct(), year, month)
	expectedId = fmt.Sprintf("%s:%s:%d:%d:%d", item.EntityDetail.CustomerId, item.GetSku(), year, month, day)

	checkBillingItemKey(t, billingItem, expectedPk, expectedId)
	assertZeroValues(t, billingItem, []string{"ActorId", "OrganizationId", "RepositoryId", "SourceUri"})
}

func Test_Item_AsYearlyItemWithPartitionKeyofType(t *testing.T) {
	usageAt := *NewUsageTimeFromTime(time.Now())
	customerId := "123"
	orgId := int64(5)
	repoId := int64(6)
	actorId := int64(7)

	item := createItemStub(customerId, orgId, repoId, actorId)
	pricingCopy := item.Pricing

	// With a fieldToIgnore provided for the ByCustomerOrgRepo partition
	year, month := usageAt.Year(), int(usageAt.Month())
	billingItem := item.AsYearlyItemWithPartitionKeyofType(ByCustomerRepo, ByCustomerOrgRepo, []string{"ActorId", "SourceUri"})
	expectedPk := fmt.Sprintf("%s:%d:byOrgAndRepo", item.EntityDetail.CustomerId, year)
	expectedId := fmt.Sprintf("%s:repo:%d:%d:%d", item.EntityDetail.CustomerId, item.EntityDetail.RepositoryId, year, month)

	checkBillingItemKey(t, billingItem, expectedPk, expectedId)
	assertZeroValues(t, billingItem, []string{"ActorId", "SourceUri"})

	// ensure original item is not changed by the changes to the billingItem
	checkOriginalItem(t, actorId, item.EntityDetail.ActorId, "ActorId")
	checkOriginalItem(t, "sourceUri", item.SourceUri, "SourceUri")

	// Without a fieldToIgnore provided for the ByCustomerOrgRepo partition
	billingItem = item.AsYearlyItemWithPartitionKeyofType(ByCustomerRepo, ByCustomerOrgRepo, nil)

	expectedPricing := item.Pricing

	checkBillingItemKey(t, billingItem, expectedPk, expectedId)

	if billingItem.Pricing != expectedPricing {
		t.Errorf("Expected pricing to be %v, got %v", expectedPricing, billingItem.Pricing)
	}
	// with fieldToIgnore provided for the ByCustomerOrg partition
	billingItem = item.AsYearlyItemWithPartitionKeyofType(ByCustomerRepo, ByCustomerOrg, []string{"ActorId", "SourceUri", "Pricing"})
	expectedPk = fmt.Sprintf("%s:org:%d:%d", item.EntityDetail.CustomerId, orgId, year)
	expectedId = fmt.Sprintf("%s:repo:%d:%d:%d", item.EntityDetail.CustomerId, item.EntityDetail.RepositoryId, year, month)

	checkBillingItemKey(t, billingItem, expectedPk, expectedId)
	assertZeroValues(t, billingItem, []string{"ActorId", "SourceUri", "Pricing"})
	// ensure the original item is not changed by the changes to the billingItem
	checkOriginalItem(t, actorId, item.EntityDetail.ActorId, "ActorId")
	checkOriginalItem(t, "sourceUri", item.SourceUri, "SourceUri")
	checkOriginalItem(t, pricingCopy.GetProduct(), item.GetProduct(), "Product")
	checkOriginalItem(t, pricingCopy.GetSku(), item.GetSku(), "Sku")

	// with fieldToIgnore provided for the ByCustomerRepo partition
	billingItem = item.AsYearlyItemWithPartitionKeyofType(ByCustomerRepo, ByCustomerRepo, []string{"ActorId", "SourceUri", "Pricing"})
	expectedPk = fmt.Sprintf("%s:repo:%d:%d", item.EntityDetail.CustomerId, item.EntityDetail.RepositoryId, year)
	expectedId = fmt.Sprintf("%s:repo:%d:%d:%d", item.EntityDetail.CustomerId, item.EntityDetail.RepositoryId, year, month)
	checkBillingItemKey(t, billingItem, expectedPk, expectedId)
	assertZeroValues(t, billingItem, []string{"ActorId", "SourceUri", "Pricing"})

	// with fieldToIgnore provided for the ByCustomer partition
	billingItem = item.AsYearlyItemWithPartitionKeyofType(ByCustomerSku, ByCustomer, []string{"ActorId", "OrganizationId", "RepositoryId", "SourceUri"})
	expectedPk = fmt.Sprintf("%s:%d", item.EntityDetail.CustomerId, year)
	expectedId = fmt.Sprintf("%s:%s:%d:%d", item.EntityDetail.CustomerId, item.GetSku(), year, month)
	checkBillingItemKey(t, billingItem, expectedPk, expectedId)
	assertZeroValues(t, billingItem, []string{"ActorId", "OrganizationId", "RepositoryId", "SourceUri"})

	// With fieldToIgnore provided for ByCustomerSku partition
	billingItem = item.AsYearlyItemWithPartitionKeyofType(ByCustomerSku, ByCustomerSku, []string{"ActorId", "OrganizationId", "RepositoryId", "SourceUri"})
	expectedPk = fmt.Sprintf("%s:%s:%d", item.EntityDetail.CustomerId, item.GetSku(), year)
	expectedId = fmt.Sprintf("%s:%s:%d:%d", item.EntityDetail.CustomerId, item.GetSku(), year, month)

	checkBillingItemKey(t, billingItem, expectedPk, expectedId)
	assertZeroValues(t, billingItem, []string{"ActorId", "OrganizationId", "RepositoryId", "SourceUri"})

	// With fieldToIgnore provided for ByCustomerProduct partition
	billingItem = item.AsYearlyItemWithPartitionKeyofType(ByCustomerSku, ByCustomerProduct, []string{"ActorId", "OrganizationId", "RepositoryId", "SourceUri"})
	expectedPk = fmt.Sprintf("%s:%s:%d", item.EntityDetail.CustomerId, item.GetProduct(), year)
	expectedId = fmt.Sprintf("%s:%s:%d:%d", item.EntityDetail.CustomerId, item.GetSku(), year, month)

	checkBillingItemKey(t, billingItem, expectedPk, expectedId)
	assertZeroValues(t, billingItem, []string{"ActorId", "OrganizationId", "RepositoryId", "SourceUri"})
}

func Test_Item_ignoreFields(t *testing.T) {
	item := createItemStub("123", 5, 6, 7)

	item.ignoreFields([]string{"Amounts"})

	assertZeroValues(t, item, []string{"Amounts"})
	if item.GetProduct() != "actions" {
		t.Errorf("Expected product to be 'actions', got %s", item.GetProduct())
	}
}

func Test_Item_GetMeterType(t *testing.T) {
	item := createItemStub("123", 5, 6, 7)

	if item.GetMeterType() != PricingMeterDefault {
		t.Errorf("Expected meter type to be %v, got %v", PricingMeterDefault, item.GetMeterType())
	}
	item.Pricing = nil
	if item.GetMeterType() != PricingMeterDefault {
		t.Errorf("Expected meter type to be %v, got %v", PricingMeterDefault, item.GetMeterType())
	}
}

func Test_Item_GetPrice(t *testing.T) {
	item := createItemStub("123", 5, 6, 7)

	if item.GetPrice() != 3000000000 {
		t.Errorf("Expected price to be %d, got %d", 3000000000, item.GetPrice())
	}

	item.Pricing = nil
	if item.GetPrice() != 0 {
		t.Errorf("Expected price to be 0, got %d", item.GetPrice())
	}
}

func Test_Item_GetAzureMeterId(t *testing.T) {
	item := createItemStub("123", 5, 6, 7)
	if item.GetAzureMeterId() != item.Pricing.AzureMeterId {
		t.Errorf("Expected azure meter id to be %s, got %s", item.Pricing.AzureMeterId, item.GetAzureMeterId())
	}

	item.Pricing = nil
	if item.GetAzureMeterId() != "" {
		t.Errorf("Expected azure meter id to be '', got %s", item.GetAzureMeterId())
	}
}
func Test_Item_ToNetUsageItemProto(t *testing.T) {
	item := createItemStub("123", 5, 6, 7)

	// Discount data is not available, like for requests for org or repo level data.
	// Net and discount amounts are set to -1 to indicate they aren't available
	protoItem := item.ToNetUsageItemProto(nil, false)

	if protoItem.GetNetAmount() != -1 {
		t.Errorf("Expected net amount to -1, got %v", protoItem.GetNetAmount())
	}
	if protoItem.GetDiscountAmount() != -1 {
		t.Errorf("Expected discount amount to be -1, got %v", protoItem.GetDiscountAmount())
	}

	// Discount data is available, the customer just doesn't have a discount applied to the item.
	// Net amount is the same as the billed amount and the discount is 0
	protoItem = item.ToNetUsageItemProto(nil, true)
	expectedNetAmount := ToDecimalAmount(item.GetAmounts().BilledAmount)

	if protoItem.GetNetAmount() != expectedNetAmount {
		t.Errorf("Expected net amount to be %v, got %v", expectedNetAmount, protoItem.GetNetAmount())
	}
	if protoItem.GetDiscountAmount() != 0 {
		t.Errorf("Expected discount amount to be 0, got %v", protoItem.GetDiscountAmount())
	}

	// Discount applied to the item. Net amount is the billed amount minus the discount amount.
	discountItem := &DiscountItem{
		DiscountAmount: 100,
	}
	expectedNetAmount = ToDecimalAmount(item.GetAmounts().BilledAmount - discountItem.DiscountAmount)
	expectedDiscountAmount := ToDecimalAmount(discountItem.DiscountAmount)
	protoItem = item.ToNetUsageItemProto(discountItem, true)

	if protoItem.GetNetAmount() != expectedNetAmount {
		t.Errorf("Expected net amount to be %v, got %v", expectedNetAmount, protoItem.GetNetAmount())
	}
	if protoItem.GetDiscountAmount() != expectedDiscountAmount {
		t.Errorf("Expected discount amount to be %v, got %v", expectedDiscountAmount, protoItem.GetDiscountAmount())
	}
}

func checkBillingItemKey(t *testing.T, billingItem *Item, expectedPk string, expectedId string) {
	if billingItem.PartitionKey != expectedPk {
		t.Errorf("Expected partitionKey to be %s, got %s", expectedPk, billingItem.PartitionKey)
	}
	if billingItem.Id != expectedId {
		t.Errorf("Expected id to be %s, got %s", expectedId, billingItem.Id)
	}
}

func assertZeroValues(t *testing.T, billingItem *Item, fields []string) {
	for _, field := range fields {
		switch field {
		case "ActorId":
			if billingItem.EntityDetail.ActorId != 0 {
				t.Errorf("Expected actorId to be 0, got %d", billingItem.EntityDetail.ActorId)
			}
		case "OrganizationId":
			if billingItem.EntityDetail.OrganizationId != 0 {
				t.Errorf("Expected organizationId to be 0, got %d", billingItem.EntityDetail.OrganizationId)
			}
		case "RepositoryId":
			if billingItem.EntityDetail.RepositoryId != 0 {
				t.Errorf("Expected repositoryId to be 0, got %d", billingItem.EntityDetail.RepositoryId)
			}
		case "SourceUri":
			if billingItem.SourceUri != "" {
				t.Errorf("Expected sourceUri to be empty, got %s", billingItem.SourceUri)
			}
		case "Pricing":
			if billingItem.Pricing != nil {
				t.Errorf("Expected pricing to be nil, got %v", billingItem.Pricing)
			}
		case "Product":
			if billingItem.GetProduct() != "" {
				t.Errorf("Expected product to be empty, got %s", billingItem.GetProduct())
			}
		case "Amounts":
			if billingItem.Amounts != nil {
				t.Errorf("Expected amounts to be nil, got %v", billingItem.Amounts)
			}
		default:
			t.Errorf("Unknown field: %s", field)
		}
	}
}

func createItemStub(customerId string, orgId, repoId, actorId int64) (item *Item) {
	return &Item{
		Key: Key{
			PartitionKey: "pk",
			Id:           "id",
		},
		Pricing: &Pricing{
			Product:      "actions",
			Sku:          "actions_linux",
			FriendlyName: "Actions Linux",
			UnitType:     UnitTypeMinutes,
			AzureMeterId: "meterId",
			MeterType:    PricingMeterDefault,
			Price:        3000000000,
		},
		Amounts: &Amounts{
			BilledAmount:           6000000000,
			Quantity:               2000000000,
			FullQuantity:           3000000000,
			AppliedCostPerQuantity: 3000000000,
		},
		EntityDetail: &EntityDetail{
			CostCenterDetail: &CostCenterDetail{
				EnterpriseCustomerId: customerId,
				CostCenterUUID:       "",
				IsCostCenterProxy:    false,
			},
			OrganizationId: orgId,
			RepositoryId:   repoId,
			ActorId:        actorId,
			CustomerId:     customerId,
		},
		SourceUri: "sourceUri",
		UsageAt:   *NewUsageTimeFromTime(time.Now()),
	}
}

func checkOriginalItem(t *testing.T, expected, actual interface{}, fieldName string) {
	if expected != actual {
		t.Errorf("Expected %s to retain original value of '%v', but got '%v'", fieldName, expected, actual)
	}
}
