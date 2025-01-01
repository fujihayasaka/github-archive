package models

import (
	"encoding/json"
	"testing"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/onsi/gomega"
)

func Test_Key_GetLoggerFields(t *testing.T) {
	g := gomega.NewGomegaWithT(t)

	key := Key{}
	fields := key.GetLoggerFields()

	g.Expect(fields).To(gomega.Equal([]kvp.Field{
		kvp.String("db.cosmosdb.partition_key", ""),
		kvp.String("db.cosmosdb.document_id", ""),
	}))

	key = Key{
		PartitionKey: "abc",
		Id:           "123",
	}
	fields = key.GetLoggerFields()

	g.Expect(fields).To(gomega.Equal([]kvp.Field{
		kvp.String("db.cosmosdb.partition_key", "abc"),
		kvp.String("db.cosmosdb.document_id", "123"),
	}))
}

func Test_HandlesMigratedFields(t *testing.T) {
	i := &Item{
		Amounts: &Amounts{
			BilledAmount:           1,
			Quantity:               2,
			AppliedCostPerQuantity: 3,
		},
	}
	migratedItem := &migratedItem{
		Product:           "product",
		Sku:               "sku",
		UnmarshalAbleItem: (*UnmarshalAbleItem)(i),
	}

	data, _ := json.Marshal(migratedItem)

	var item Item
	err := json.Unmarshal(data, &item)
	if err != nil {
		t.Error(err)
		t.Fail()
	}

	if item.Pricing == nil {
		t.Error("Expected pricing to be migrated")
		t.Fail()
	}

	if item.GetProduct() != migratedItem.Product {
		t.Errorf("Expected product to be %s, got %s", migratedItem.Product, item.GetProduct())
	}

	if item.GetSku() != migratedItem.Sku {
		t.Errorf("Expected sku to be %s, got %s", migratedItem.Sku, item.GetSku())
	}
}

func Test_HandlesDefaultUnmarshal_WithNoProduct_Sku(t *testing.T) {
	i := &Item{
		Amounts: &Amounts{
			BilledAmount:           1,
			Quantity:               2,
			AppliedCostPerQuantity: 3,
		},
	}

	data, _ := json.Marshal(i)

	var item Item
	err := json.Unmarshal(data, &item)
	if err != nil {
		t.Error(err)
		t.Fail()
	}

	if item.Pricing == nil {
		t.Error("Expected pricing to be migrated")
		t.Fail()
	}

	if item.GetProduct() != "" {
		t.Errorf("Expected product to be %s, got %s", "", item.GetProduct())
	}

	if item.GetSku() != "" {
		t.Errorf("Expected sku to be %s, got %s", "", item.GetSku())
	}
}

func Test_HandlesDefaultUnmarshal_WithPricingProduct_Sku(t *testing.T) {
	i := &Item{
		Amounts: &Amounts{
			BilledAmount:           1,
			Quantity:               2,
			AppliedCostPerQuantity: 3,
		},
		Pricing: &Pricing{
			Product: "product",
			Sku:     "sku",
		},
	}

	data, _ := json.Marshal(i)

	var item Item
	err := json.Unmarshal(data, &item)
	if err != nil {
		t.Error(err)
		t.Fail()
	}

	if item.Pricing == nil {
		t.Error("Expected pricing to be migrated")
		t.Fail()
	}

	if item.GetProduct() != i.GetProduct() {
		t.Errorf("Expected product to be %s, got %s", i.GetProduct(), item.GetProduct())
	}

	if item.GetSku() != i.GetSku() {
		t.Errorf("Expected sku to be %s, got %s", i.GetSku(), item.GetSku())
	}
}

func Test_ActiveType(t *testing.T) {
	hourly := Hourly

	if !hourly.Includes(H) {
		t.Error("Hourly should include hourly")
		t.Fail()
	}
	if hourly.Includes(D) {
		t.Error("Hourly should not include daily")
		t.Fail()
	}
	if hourly.Includes(M) {
		t.Error("Hourly should not include monthly")
		t.Fail()
	}

	daily := Daily
	if !daily.Includes(H) {
		t.Error("Daily should include hourly")
		t.Fail()
	}
	if !daily.Includes(D) {
		t.Error("Daily should not include daily")
		t.Fail()
	}
	if daily.Includes(M) {
		t.Error("Daily should not include monthly")
		t.Fail()
	}

	monthly := Monthly
	if !monthly.Includes(H) {
		t.Error("Monthly should include hourly")
		t.Fail()
	}
	if !monthly.Includes(D) {
		t.Error("Monthly should not include daily")
		t.Fail()
	}
	if !monthly.Includes(M) {
		t.Error("Monthly should not include monthly")
		t.Fail()
	}
}
