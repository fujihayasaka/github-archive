package models

import (
	"fmt"
	"testing"
	"time"

	"github.com/github/billing-platform/internal/nano"
	"github.com/github/billing-platform/lib/twirp/proto"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/onsi/gomega"
	"github.com/stretchr/testify/assert"
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
	item := createItemStub("4", 5, 6, 7, nil)

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
	item := createItemStub("4", 5, 6, 7, nil)

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
	item := createItemStub("4", 5, 6, 7, nil)

	billingItem := item.AsItemWithEventPartitionKey()
	expectedPK := fmt.Sprintf("%s:%s:events", item.EntityDetail.CustomerId, item.GetSku())

	if billingItem.PartitionKey != expectedPK {
		t.Errorf("Expected customer ID to be %s, got %s", expectedPK, billingItem.PartitionKey)
	}
}

func Test_Item_AsItemWithEventPartitionKeyWithYearMonth(t *testing.T) {
	item := createItemStub("123", 5, 6, 7, nil)

	billingItem := item.AsItemWithEventPartitionKeyWithYearMonth()
	expectedPK := fmt.Sprintf("%s:%s:events:%d:%d", item.EntityDetail.CustomerId, item.GetSku(), item.UsageAt.Year(), item.UsageAt.Month())
	expectedId := "pk" // default partition key set in the stub

	if billingItem.Id != expectedId {
		t.Errorf("Expected ID to be %s, got %s", expectedId, billingItem.Id)
	}

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

	item := createItemStub(customerId, orgId, repoId, actorId, nil)
	pricingCopy := *item.Pricing

	year, month, day, hour := usageAt.Year(), int(usageAt.Month()), usageAt.Day(), usageAt.Hour()

	tests := []struct {
		name           string
		partitionType1 UsagePartitionType
		partitionType2 UsagePartitionType
		fieldsToIgnore []string
		expectedPk     string
		expectedId     string
	}{
		{
			name:           "ByCustomerOrgRepo with Pricing ignored",
			partitionType1: ByCustomerRepo,
			partitionType2: ByCustomerOrgRepo,
			fieldsToIgnore: []string{"Pricing"},
			expectedPk:     fmt.Sprintf("%s:%d:%d:%d:byOrgAndRepo", item.EntityDetail.CustomerId, year, month, day),
			expectedId:     fmt.Sprintf("%s:repo:%d:%d:%d:%d:%d", item.EntityDetail.CustomerId, item.EntityDetail.RepositoryId, year, month, day, hour),
		},
		{
			name:           "ByCustomerOrgRepo without fields ignored",
			partitionType1: ByCustomerRepo,
			partitionType2: ByCustomerOrgRepo,
			fieldsToIgnore: nil,
			expectedPk:     fmt.Sprintf("%s:%d:%d:%d:byOrgAndRepo", item.EntityDetail.CustomerId, year, month, day),
			expectedId:     fmt.Sprintf("%s:repo:%d:%d:%d:%d:%d", item.EntityDetail.CustomerId, item.EntityDetail.RepositoryId, year, month, day, hour),
		},
		{
			name:           "ByCustomerOrg with multiple fields ignored",
			partitionType1: ByCustomerRepo,
			partitionType2: ByCustomerOrg,
			fieldsToIgnore: []string{"Pricing", "SourceUri", "ActorId"},
			expectedPk:     fmt.Sprintf("%s:org:%d:%d:%d:%d", item.EntityDetail.CustomerId, orgId, year, month, day),
			expectedId:     fmt.Sprintf("%s:repo:%d:%d:%d:%d:%d", item.EntityDetail.CustomerId, item.EntityDetail.RepositoryId, year, month, day, hour),
		},
		{
			name:           "ByCustomerSku with multiple fields ignored",
			partitionType1: ByCustomerSku,
			partitionType2: ByCustomerSku,
			fieldsToIgnore: []string{"ActorId", "OrganizationId", "RepositoryId", "SourceUri"},
			expectedPk:     fmt.Sprintf("%s:%s:%d:%d:%d", item.EntityDetail.CustomerId, item.GetSku(), year, month, day),
			expectedId:     fmt.Sprintf("%s:%s:%d:%d:%d:%d", item.EntityDetail.CustomerId, item.GetSku(), year, month, day, hour),
		},
		{
			name:           "ByCustomerProduct with multiple fields ignored",
			partitionType1: ByCustomerSku,
			partitionType2: ByCustomerProduct,
			fieldsToIgnore: []string{"ActorId", "OrganizationId", "RepositoryId", "SourceUri"},
			expectedPk:     fmt.Sprintf("%s:%s:%d:%d:%d", item.EntityDetail.CustomerId, item.GetProduct(), year, month, day),
			expectedId:     fmt.Sprintf("%s:%s:%d:%d:%d:%d", item.EntityDetail.CustomerId, item.GetSku(), year, month, day, hour),
		},
		{
			name:           "ByCustomer with multiple fields ignored",
			partitionType1: ByCustomerSku,
			partitionType2: ByCustomer,
			fieldsToIgnore: []string{"ActorId", "OrganizationId", "RepositoryId", "SourceUri"},
			expectedPk:     fmt.Sprintf("%s:%d:%d:%d", item.EntityDetail.CustomerId, year, month, day),
			expectedId:     fmt.Sprintf("%s:%s:%d:%d:%d:%d", item.EntityDetail.CustomerId, item.GetSku(), year, month, day, hour),
		},
		{
			name:           "ByCustomerOrgByProductSku with multiple fields ignored",
			partitionType1: ByCustomerSku,
			partitionType2: ByCustomerOrgByProductSku,
			fieldsToIgnore: []string{"ActorId", "RepositoryId", "SourceUri"},
			expectedPk:     fmt.Sprintf("%s:org:%d:%d:%d:%d:byProductSku", item.EntityDetail.CustomerId, item.EntityDetail.OrganizationId, year, month, day),
			expectedId:     fmt.Sprintf("%s:%s:%d:%d:%d:%d", item.EntityDetail.CustomerId, item.GetSku(), year, month, day, hour),
		},
		{
			name:           "ByCustomerRepoByProductSku with multiple fields ignored",
			partitionType1: ByCustomerSku,
			partitionType2: ByCustomerRepoByProductSku,
			fieldsToIgnore: []string{"ActorId", "SourceUri"},
			expectedPk:     fmt.Sprintf("%s:repo:%d:%d:%d:%d:byProductSku", item.EntityDetail.CustomerId, item.EntityDetail.RepositoryId, year, month, day),
			expectedId:     fmt.Sprintf("%s:%s:%d:%d:%d:%d", item.EntityDetail.CustomerId, item.GetSku(), year, month, day, hour),
		},
		{
			name:           "ByCustomerOrgRepoProductSku with multiple fields ignored",
			partitionType1: ByOrgRepoProductSku,
			partitionType2: ByCustomerOrgRepoProductSku,
			fieldsToIgnore: []string{"ActorId", "SourceUri"},
			expectedPk:     fmt.Sprintf("%s:%d:%d:%d:byOrgRepoProductSku", item.EntityDetail.CustomerId, year, month, day),
			expectedId:     fmt.Sprintf("customer:%s:org:%d:repo:%d:product:%s:sku:%s:%d:%d:%d:%d", item.EntityDetail.CustomerId, item.EntityDetail.OrganizationId, item.EntityDetail.RepositoryId, item.GetProduct(), item.GetSku(), year, month, day, hour),
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			billingItem := item.AsDailyItemWithPartitionKeyofType(tt.partitionType1, tt.partitionType2, tt.fieldsToIgnore)
			checkBillingItemKey(t, billingItem, tt.expectedPk, tt.expectedId)
			assertZeroValues(t, billingItem, tt.fieldsToIgnore)
		})
	}

	// ensure item is not changed by updates to the billingItem
	checkOriginalItem(t, actorId, item.EntityDetail.ActorId, "ActorId")
	checkOriginalItem(t, "sourceUri", item.SourceUri, "SourceUri")
	checkOriginalItem(t, pricingCopy.Product, item.GetProduct(), "Product")
	checkOriginalItem(t, pricingCopy.GetSku(), item.GetSku(), "Sku")
	checkOriginalItem(t, orgId, item.EntityDetail.OrganizationId, "OrganizationId")
	checkOriginalItem(t, repoId, item.EntityDetail.RepositoryId, "RepositoryId")
}

func Test_Item_AsMonthlyItemWithPartitionKeyofType(t *testing.T) {
	usageAt := *NewUsageTimeFromTime(time.Now())
	customerId := "123"
	orgId := int64(5)
	repoId := int64(6)
	actorId := int64(7)

	item := createItemStub(customerId, orgId, repoId, actorId, nil)
	pricingCopy := *item.Pricing

	year, month, day := usageAt.Year(), int(usageAt.Month()), usageAt.Day()

	tests := []struct {
		name           string
		partitionType1 UsagePartitionType
		partitionType2 UsagePartitionType
		fieldsToIgnore []string
		expectedPk     string
		expectedId     string
	}{
		{
			name:           "ByCustomerOrgRepo with Pricing and ActorId ignored",
			partitionType1: ByCustomerRepo,
			partitionType2: ByCustomerOrgRepo,
			fieldsToIgnore: []string{"Pricing", "ActorId"},
			expectedPk:     fmt.Sprintf("%s:%d:%d:byOrgAndRepo", item.EntityDetail.CustomerId, year, month),
			expectedId:     fmt.Sprintf("%s:repo:%d:%d:%d:%d", item.EntityDetail.CustomerId, item.EntityDetail.RepositoryId, year, month, day),
		},
		{
			name:           "ByCustomerOrgRepo without fields ignored",
			partitionType1: ByCustomerRepo,
			partitionType2: ByCustomerOrgRepo,
			fieldsToIgnore: nil,
			expectedPk:     fmt.Sprintf("%s:%d:%d:byOrgAndRepo", item.EntityDetail.CustomerId, year, month),
			expectedId:     fmt.Sprintf("%s:repo:%d:%d:%d:%d", item.EntityDetail.CustomerId, item.EntityDetail.RepositoryId, year, month, day),
		},
		{
			name:           "ByCustomerOrg with multiple fields ignored",
			partitionType1: ByCustomerRepo,
			partitionType2: ByCustomerOrg,
			fieldsToIgnore: []string{"Pricing", "ActorId", "SourceUri"},
			expectedPk:     fmt.Sprintf("%s:org:%d:%d:%d", item.EntityDetail.CustomerId, orgId, year, month),
			expectedId:     fmt.Sprintf("%s:repo:%d:%d:%d:%d", item.EntityDetail.CustomerId, item.EntityDetail.RepositoryId, year, month, day),
		},
		{
			name:           "ByCustomerRepo with multiple fields ignored",
			partitionType1: ByCustomerRepo,
			partitionType2: ByCustomerRepo,
			fieldsToIgnore: []string{"Pricing", "ActorId", "SourceUri"},
			expectedPk:     fmt.Sprintf("%s:repo:%d:%d:%d", item.EntityDetail.CustomerId, item.EntityDetail.RepositoryId, year, month),
			expectedId:     fmt.Sprintf("%s:repo:%d:%d:%d:%d", item.EntityDetail.CustomerId, item.EntityDetail.RepositoryId, year, month, day),
		},
		{
			name:           "ByCustomerSku with multiple fields ignored",
			partitionType1: ByCustomerSku,
			partitionType2: ByCustomerSku,
			fieldsToIgnore: []string{"ActorId", "OrganizationId", "RepositoryId", "SourceUri"},
			expectedPk:     fmt.Sprintf("%s:%s:%d:%d", item.EntityDetail.CustomerId, item.GetSku(), year, month),
			expectedId:     fmt.Sprintf("%s:%s:%d:%d:%d", item.EntityDetail.CustomerId, item.GetSku(), year, month, day),
		},
		{
			name:           "ByCustomer with multiple fields ignored",
			partitionType1: ByCustomerSku,
			partitionType2: ByCustomer,
			fieldsToIgnore: []string{"ActorId", "OrganizationId", "RepositoryId", "SourceUri"},
			expectedPk:     fmt.Sprintf("%s:%d:%d", item.EntityDetail.CustomerId, year, month),
			expectedId:     fmt.Sprintf("%s:%s:%d:%d:%d", item.EntityDetail.CustomerId, item.GetSku(), year, month, day),
		},
		{
			name:           "ByCustomerProduct with multiple fields ignored",
			partitionType1: ByCustomerSku,
			partitionType2: ByCustomerProduct,
			fieldsToIgnore: []string{"ActorId", "OrganizationId", "RepositoryId", "SourceUri"},
			expectedPk:     fmt.Sprintf("%s:%s:%d:%d", item.EntityDetail.CustomerId, item.GetProduct(), year, month),
			expectedId:     fmt.Sprintf("%s:%s:%d:%d:%d", item.EntityDetail.CustomerId, item.GetSku(), year, month, day),
		},
		{
			name:           "ByCustomerOrgByProductSku with multiple fields ignored",
			partitionType1: ByCustomerSku,
			partitionType2: ByCustomerOrgByProductSku,
			fieldsToIgnore: []string{"ActorId", "RepositoryId", "SourceUri"},
			expectedPk:     fmt.Sprintf("%s:org:%d:%d:%d:byProductSku", item.EntityDetail.CustomerId, item.EntityDetail.OrganizationId, year, month),
			expectedId:     fmt.Sprintf("%s:%s:%d:%d:%d", item.EntityDetail.CustomerId, item.GetSku(), year, month, day),
		},
		{
			name:           "ByCustomerRepoByProductSku with multiple fields ignored",
			partitionType1: ByCustomerSku,
			partitionType2: ByCustomerRepoByProductSku,
			fieldsToIgnore: []string{"ActorId", "SourceUri"},
			expectedPk:     fmt.Sprintf("%s:repo:%d:%d:%d:byProductSku", item.EntityDetail.CustomerId, item.EntityDetail.RepositoryId, year, month),
			expectedId:     fmt.Sprintf("%s:%s:%d:%d:%d", item.EntityDetail.CustomerId, item.GetSku(), year, month, day),
		},
		{
			name:           "ByCustomerOrgRepoProductSku with multiple fields ignored",
			partitionType1: ByOrgRepoProductSku,
			partitionType2: ByCustomerOrgRepoProductSku,
			fieldsToIgnore: []string{"ActorId", "SourceUri"},
			expectedPk:     fmt.Sprintf("%s:%d:%d:byOrgRepoProductSku", item.EntityDetail.CustomerId, year, month),
			expectedId:     fmt.Sprintf("customer:%s:org:%d:repo:%d:product:%s:sku:%s:%d:%d:%d", item.EntityDetail.CustomerId, item.EntityDetail.OrganizationId, item.EntityDetail.RepositoryId, item.GetProduct(), item.GetSku(), year, month, day),
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			billingItem := item.AsMonthlyItemWithPartitionKeyofType(tt.partitionType1, tt.partitionType2, tt.fieldsToIgnore)
			checkBillingItemKey(t, billingItem, tt.expectedPk, tt.expectedId)
			assertZeroValues(t, billingItem, tt.fieldsToIgnore)
		})
	}

	// ensure the original item is not changed by the changes to the billingItem
	checkOriginalItem(t, actorId, item.EntityDetail.ActorId, "ActorId")
	checkOriginalItem(t, pricingCopy.Product, item.GetProduct(), "Product")
	checkOriginalItem(t, pricingCopy.GetSku(), item.GetSku(), "Sku")
	checkOriginalItem(t, orgId, item.EntityDetail.OrganizationId, "OrganizationId")
	checkOriginalItem(t, repoId, item.EntityDetail.RepositoryId, "RepositoryId")
	checkOriginalItem(t, "sourceUri", item.SourceUri, "SourceUri")
}

func Test_Item_AsYearlyItemWithPartitionKeyofType(t *testing.T) {
	usageAt := *NewUsageTimeFromTime(time.Now())
	customerId := "123"
	orgId := int64(5)
	repoId := int64(6)
	actorId := int64(7)

	item := createItemStub(customerId, orgId, repoId, actorId, nil)
	pricingCopy := *item.Pricing

	year, month := usageAt.Year(), int(usageAt.Month())

	tests := []struct {
		name           string
		partitionType1 UsagePartitionType
		partitionType2 UsagePartitionType
		fieldsToIgnore []string
		expectedPk     string
		expectedId     string
	}{
		{
			name:           "ByCustomerOrgRepo with ActorId and SourceUri ignored",
			partitionType1: ByCustomerRepo,
			partitionType2: ByCustomerOrgRepo,
			fieldsToIgnore: []string{"ActorId", "SourceUri"},
			expectedPk:     fmt.Sprintf("%s:%d:byOrgAndRepo", item.EntityDetail.CustomerId, year),
			expectedId:     fmt.Sprintf("%s:repo:%d:%d:%d", item.EntityDetail.CustomerId, item.EntityDetail.RepositoryId, year, month),
		},
		{
			name:           "ByCustomerOrgRepo without fields ignored",
			partitionType1: ByCustomerRepo,
			partitionType2: ByCustomerOrgRepo,
			fieldsToIgnore: nil,
			expectedPk:     fmt.Sprintf("%s:%d:byOrgAndRepo", item.EntityDetail.CustomerId, year),
			expectedId:     fmt.Sprintf("%s:repo:%d:%d:%d", item.EntityDetail.CustomerId, item.EntityDetail.RepositoryId, year, month),
		},
		{
			name:           "ByCustomerOrg with multiple fields ignored",
			partitionType1: ByCustomerRepo,
			partitionType2: ByCustomerOrg,
			fieldsToIgnore: []string{"ActorId", "SourceUri", "Pricing"},
			expectedPk:     fmt.Sprintf("%s:org:%d:%d", item.EntityDetail.CustomerId, orgId, year),
			expectedId:     fmt.Sprintf("%s:repo:%d:%d:%d", item.EntityDetail.CustomerId, item.EntityDetail.RepositoryId, year, month),
		},
		{
			name:           "ByCustomerRepo with multiple fields ignored",
			partitionType1: ByCustomerRepo,
			partitionType2: ByCustomerRepo,
			fieldsToIgnore: []string{"ActorId", "SourceUri", "Pricing"},
			expectedPk:     fmt.Sprintf("%s:repo:%d:%d", item.EntityDetail.CustomerId, item.EntityDetail.RepositoryId, year),
			expectedId:     fmt.Sprintf("%s:repo:%d:%d:%d", item.EntityDetail.CustomerId, item.EntityDetail.RepositoryId, year, month),
		},
		{
			name:           "ByCustomer with multiple fields ignored",
			partitionType1: ByCustomerSku,
			partitionType2: ByCustomer,
			fieldsToIgnore: []string{"ActorId", "OrganizationId", "RepositoryId", "SourceUri"},
			expectedPk:     fmt.Sprintf("%s:%d", item.EntityDetail.CustomerId, year),
			expectedId:     fmt.Sprintf("%s:%s:%d:%d", item.EntityDetail.CustomerId, item.GetSku(), year, month),
		},
		{
			name:           "ByCustomerSku with multiple fields ignored",
			partitionType1: ByCustomerSku,
			partitionType2: ByCustomerSku,
			fieldsToIgnore: []string{"ActorId", "OrganizationId", "RepositoryId", "SourceUri"},
			expectedPk:     fmt.Sprintf("%s:%s:%d", item.EntityDetail.CustomerId, item.GetSku(), year),
			expectedId:     fmt.Sprintf("%s:%s:%d:%d", item.EntityDetail.CustomerId, item.GetSku(), year, month),
		},
		{
			name:           "ByCustomerProduct with multiple fields ignored",
			partitionType1: ByCustomerSku,
			partitionType2: ByCustomerProduct,
			fieldsToIgnore: []string{"ActorId", "OrganizationId", "RepositoryId", "SourceUri"},
			expectedPk:     fmt.Sprintf("%s:%s:%d", item.EntityDetail.CustomerId, item.GetProduct(), year),
			expectedId:     fmt.Sprintf("%s:%s:%d:%d", item.EntityDetail.CustomerId, item.GetSku(), year, month),
		},
		{
			name:           "ByCustomerOrgByProductSku with multiple fields ignored",
			partitionType1: ByCustomerSku,
			partitionType2: ByCustomerOrgByProductSku,
			fieldsToIgnore: []string{"ActorId", "RepositoryId", "SourceUri"},
			expectedPk:     fmt.Sprintf("%s:org:%d:%d:byProductSku", item.EntityDetail.CustomerId, item.EntityDetail.OrganizationId, year),
			expectedId:     fmt.Sprintf("%s:%s:%d:%d", item.EntityDetail.CustomerId, item.GetSku(), year, month),
		},
		{
			name:           "ByCustomerRepoByProductSku with multiple fields ignored",
			partitionType1: ByCustomerSku,
			partitionType2: ByCustomerRepoByProductSku,
			fieldsToIgnore: []string{"ActorId", "SourceUri"},
			expectedPk:     fmt.Sprintf("%s:repo:%d:%d:byProductSku", item.EntityDetail.CustomerId, item.EntityDetail.RepositoryId, year),
			expectedId:     fmt.Sprintf("%s:%s:%d:%d", item.EntityDetail.CustomerId, item.GetSku(), year, month),
		},
		{
			name:           "ByCustomerOrgRepoProductSku with multiple fields ignored",
			partitionType1: ByOrgRepoProductSku,
			partitionType2: ByCustomerOrgRepoProductSku,
			fieldsToIgnore: []string{"ActorId", "SourceUri"},
			expectedPk:     fmt.Sprintf("%s:%d:byOrgRepoProductSku", item.EntityDetail.CustomerId, year),
			expectedId:     fmt.Sprintf("customer:%s:org:%d:repo:%d:product:%s:sku:%s:%d:%d", item.EntityDetail.CustomerId, item.EntityDetail.OrganizationId, item.EntityDetail.RepositoryId, item.GetProduct(), item.GetSku(), year, month),
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			billingItem := item.AsYearlyItemWithPartitionKeyofType(tt.partitionType1, tt.partitionType2, tt.fieldsToIgnore)
			checkBillingItemKey(t, billingItem, tt.expectedPk, tt.expectedId)
			assertZeroValues(t, billingItem, tt.fieldsToIgnore)
		})
	}

	// ensure the original item is not changed by the changes to the billingItem
	checkOriginalItem(t, actorId, item.EntityDetail.ActorId, "ActorId")
	checkOriginalItem(t, pricingCopy.Product, item.GetProduct(), "Product")
	checkOriginalItem(t, pricingCopy.GetSku(), item.GetSku(), "Sku")
	checkOriginalItem(t, orgId, item.EntityDetail.OrganizationId, "OrganizationId")
	checkOriginalItem(t, repoId, item.EntityDetail.RepositoryId, "RepositoryId")
	checkOriginalItem(t, "sourceUri", item.SourceUri, "SourceUri")
}

func Test_Item_ignoreFields(t *testing.T) {
	item := createItemStub("123", 5, 6, 7, nil)

	item.ignoreFields([]string{"Amounts"})

	assertZeroValues(t, item, []string{"Amounts"})
	if item.GetProduct() != "actions" {
		t.Errorf("Expected product to be 'actions', got %s", item.GetProduct())
	}
}

func Test_Item_GetMeterType(t *testing.T) {
	item := createItemStub("123", 5, 6, 7, nil)

	if item.GetMeterType() != PricingMeterDefault {
		t.Errorf("Expected meter type to be %v, got %v", PricingMeterDefault, item.GetMeterType())
	}
	item.Pricing = nil
	if item.GetMeterType() != PricingMeterDefault {
		t.Errorf("Expected meter type to be %v, got %v", PricingMeterDefault, item.GetMeterType())
	}
}

func Test_Item_GetPrice(t *testing.T) {
	item := createItemStub("123", 5, 6, 7, nil)

	if item.GetPrice() != 3000000000 {
		t.Errorf("Expected price to be %d, got %d", 3000000000, item.GetPrice())
	}

	item.Pricing = nil
	if item.GetPrice() != 0 {
		t.Errorf("Expected price to be 0, got %d", item.GetPrice())
	}
}

func Test_Item_GetAzureMeterId(t *testing.T) {
	item := createItemStub("123", 5, 6, 7, nil)
	if item.GetAzureMeterId() != item.Pricing.AzureMeterId {
		t.Errorf("Expected azure meter id to be %s, got %s", item.Pricing.AzureMeterId, item.GetAzureMeterId())
	}

	item.Pricing = nil
	if item.GetAzureMeterId() != "" {
		t.Errorf("Expected azure meter id to be '', got %s", item.GetAzureMeterId())
	}
}

func Test_Item_ToNetUsageItemProto(t *testing.T) {
	item := createItemStub("123", 5, 6, 7, nil)

	// Discount data is available, the customer just doesn't have a discount applied to the item.
	// Net amount is the same as the billed amount and the discount is 0
	protoItem := item.ToNetUsageItemProto(nil, false)
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
	protoItem = item.ToNetUsageItemProto(discountItem, false)

	if protoItem.GetNetAmount() != expectedNetAmount {
		t.Errorf("Expected net amount to be %v, got %v", expectedNetAmount, protoItem.GetNetAmount())
	}
	if protoItem.GetDiscountAmount() != expectedDiscountAmount {
		t.Errorf("Expected discount amount to be %v, got %v", expectedDiscountAmount, protoItem.GetDiscountAmount())
	}
}

func Test_Item_ToNetUsageItemProto_With_License_Sku_Updates(t *testing.T) {
	tests := []struct {
		name                     string
		item                     *Item
		calculateLicensedFields  bool
		expectedDailyLicenseCost float64
		expectedLicenseQty       float64
	}{
		{
			name: "February - licensed SKU with daily emissions - flag enabled",
			item: func() *Item {
				pricing := &Pricing{
					Sku:          "copilot_enterprise",
					Product:      "copilot",
					FriendlyName: "Copilot Enterprise",
					UnitType:     UnitTypeUserMonths,
				}
				item := createItemStub("customer123", 5, 6, 7, pricing)
				item.Amounts.AppliedCostPerQuantity = 3100000000
				item.Amounts.Quantity = 4000000000
				item.UsageAt = UsageTime{
					Time: time.Date(2025, time.February, 1, 0, 0, 0, 0, time.UTC),
				}
				return item
			}(),
			calculateLicensedFields: true,
			// February 2025 has 28 days
			expectedDailyLicenseCost: ToDecimalAmount(3100000000 / int64(28)),
			expectedLicenseQty:       4.0 * 28,
		},
		{
			name: "January - licensed SKU with daily emissions - flag enabled",
			item: func() *Item {
				pricing := &Pricing{
					Sku:          "copilot_enterprise",
					Product:      "copilot",
					FriendlyName: "Copilot Enterprise",
					UnitType:     UnitTypeUserMonths,
				}
				item := createItemStub("customer123", 5, 6, 7, pricing)
				item.Amounts.AppliedCostPerQuantity = 3100000000 // $31.00
				item.Amounts.Quantity = 3000000000
				item.UsageAt = UsageTime{
					Time: time.Date(2025, time.January, 15, 0, 0, 0, 0, time.UTC),
				}
				return item
			}(),
			calculateLicensedFields: true,
			// January 2025 has 31 days
			expectedDailyLicenseCost: ToDecimalAmount(3100000000 / int64(31)),
			expectedLicenseQty:       3.0 * 31,
		},
		{
			name: "with a non licensed sku (actions linux) - flag enabled",
			item: func() *Item {
				item := createItemStub("customer123", 5, 6, 7, nil)
				return item
			}(),
			calculateLicensedFields:  true,
			expectedDailyLicenseCost: 0, // Should be 0 for non-licensed SKUs
			expectedLicenseQty:       0, // Should be 0 for non-licensed SKUs
		},
		{
			name: "with a non licensed sku (actions linux) - flag disabled",
			item: func() *Item {
				item := createItemStub("customer123", 5, 6, 7, nil)
				return item
			}(),
			calculateLicensedFields:  false,
			expectedDailyLicenseCost: 0, // Should be 0 when the flag is disabled
			expectedLicenseQty:       0, // Should be 0 when the flag is disabled
		},
		{
			name: "licensed SKU - flag disabled",
			item: func() *Item {
				pricing := &Pricing{
					Sku:          "copilot_enterprise",
					Product:      "copilot",
					FriendlyName: "Copilot Enterprise",
					UnitType:     UnitTypeUserMonths,
				}
				item := createItemStub("customer123", 5, 6, 7, pricing)
				item.Amounts.AppliedCostPerQuantity = 3100000000
				item.Amounts.Quantity = 4000000000
				item.UsageAt = UsageTime{
					Time: time.Date(2025, time.February, 1, 0, 0, 0, 0, time.UTC),
				}
				return item
			}(),
			calculateLicensedFields:  false,
			expectedDailyLicenseCost: 0, // Should be 0 when the flag is disabled
			expectedLicenseQty:       0, // Should be 0 when the flag is disabled
		},
		{
			name: "January - deprecated licensed SKU - flag disabled",
			item: func() *Item {
				pricing := &Pricing{
					Sku:          "ghas_seats",
					Product:      "ghas",
					FriendlyName: "GHAS Seats",
					UnitType:     UnitTypeUserMonths,
				}
				item := createItemStub("customer123", 5, 6, 7, pricing)
				item.Amounts.AppliedCostPerQuantity = 3100000000 // $31.00
				item.Amounts.Quantity = 3000000000
				item.UsageAt = UsageTime{
					Time: time.Date(2025, time.January, 15, 0, 0, 0, 0, time.UTC),
				}
				return item
			}(),
			calculateLicensedFields:  false,
			expectedDailyLicenseCost: 0, // should be 0 since flag is disabled
			expectedLicenseQty:       0, // should be 0 since flag is disabled
		},
		{
			name: "January - deprecated licensed SKU - flag enabled",
			item: func() *Item {
				pricing := &Pricing{
					Sku:          "ghas_seats",
					Product:      "ghas",
					FriendlyName: "GHAS Seats",
					UnitType:     UnitTypeUserMonths,
				}
				item := createItemStub("customer123", 5, 6, 7, pricing)
				item.Amounts.AppliedCostPerQuantity = 3100000000 // $31.00
				item.Amounts.Quantity = 3000000000
				item.UsageAt = UsageTime{
					Time: time.Date(2025, time.January, 15, 0, 0, 0, 0, time.UTC),
				}
				return item
			}(),
			calculateLicensedFields:  true,
			expectedDailyLicenseCost: 0, // should be 0 for deprecated licensed SKUs
			expectedLicenseQty:       0, // should be 0 for deprecated licensed SKUs
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			protoItem := tt.item.ToNetUsageItemProto(nil, tt.calculateLicensedFields)

			assert.Equal(t, tt.expectedDailyLicenseCost, protoItem.DailyLicenseCost,
				"Daily License Cost value should match expected calculation")
			assert.Equal(t, tt.expectedLicenseQty, protoItem.DailyLicenseQuantity,
				"DailyLicenseQuantity value should match expected calculation")
		})
	}
}

func Test_UsageItem_IncrementAmounts(t *testing.T) {
	incomingItem := &UsageItem{
		GrossAmount:    20,
		NetAmount:      15,
		DiscountAmount: 5,
	}

	existingItem := &UsageItem{
		GrossAmount:    100,
		NetAmount:      50,
		DiscountAmount: 50,
	}

	existingItem.IncrementAmounts(incomingItem)
	assert.Equal(t, existingItem.GrossAmount, float64(120))
	assert.Equal(t, existingItem.NetAmount, float64(65))
	assert.Equal(t, existingItem.DiscountAmount, float64(55))
}

func Test_UsageItem_DecrementAmounts(t *testing.T) {
	incomingItem := &UsageItem{
		GrossAmount:    20,
		NetAmount:      15,
		DiscountAmount: 5,
	}

	existingItem := &UsageItem{
		GrossAmount:    100,
		NetAmount:      50,
		DiscountAmount: 50,
	}

	existingItem.DecrementAmounts(incomingItem)
	assert.Equal(t, existingItem.GrossAmount, float64(80))
	assert.Equal(t, existingItem.NetAmount, float64(35))
	assert.Equal(t, existingItem.DiscountAmount, float64(45))
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

func createItemStub(customerId string, orgId, repoId, actorId int64, pricing *Pricing) *Item {
	if pricing == nil {
		pricing = &Pricing{
			Product:      "actions",
			Sku:          "actions_linux",
			FriendlyName: "Actions Linux",
			UnitType:     UnitTypeMinutes,
			AzureMeterId: "meterId",
			MeterType:    PricingMeterDefault,
			Price:        3000000000,
		}
	}

	return &Item{
		Key: Key{
			PartitionKey: "pk",
			Id:           "id",
		},
		Pricing: pricing,
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
