package models

import "testing"

func Test_GetProductFromPartitionKey(t *testing.T) {
	// in partition key with product
	key := Key{PartitionKey: "123:actions:2024:3:18"}
	product := key.GetProductFromPartitionKey()

	if product != "actions" {
		t.Errorf("expected product to be actions, got %s", product)
	}

	// in partition key with product sku
	key = Key{PartitionKey: "123:actions_linux:2024:3:18"}
	product = key.GetProductFromPartitionKey()

	if product != "actions" {
		t.Errorf("expected product to be actions, got %s", product)
	}

	// in partition key without product or sku
	key = Key{PartitionKey: "123:2024:3:18"}
	product = key.GetProductFromPartitionKey()

	if product != "" {
		t.Errorf("expected product to be empty, got %s", product)
	}
}

func Test_GetProductSkuFromPartitionKey(t *testing.T) {
	// in partition key with product sku
	key := Key{PartitionKey: "123:actions_linux:2024:3:18"}
	sku := key.GetProductSkuFromPartitionKey()

	if sku != "actions_linux" {
		t.Errorf("expected sku to be actions_linux, got %s", sku)
	}

	// in partition key with product
	key = Key{PartitionKey: "123:actions:2024:3:18"}
	sku = key.GetProductSkuFromPartitionKey()

	if sku != "" {
		t.Errorf("expected sku to be empty, got %s", sku)
	}

	// in partition key without product or sku
	key = Key{PartitionKey: "123:2024:3:18"}
	sku = key.GetProductSkuFromPartitionKey()

	if sku != "" {
		t.Errorf("expected sku to be empty, got %s", sku)
	}
}

func Test_GetPartitionTemplate(t *testing.T) {
	key := Key{PartitionKey: "123:actions_linux:2024:3:18:9"}
	template := key.GetPartitionTemplate()

	if template != "customerID:skuName:YYYY:MM:DD:HH" {
		t.Errorf("expected template to be customerID:skuName:YYYY:MM:DD:HH, got %s", template)
	}

	key = Key{PartitionKey: "123:actions:2024:3:18:9"}
	template = key.GetPartitionTemplate()

	if template != "customerID:productName:YYYY:MM:DD:HH" {
		t.Errorf("expected template to be customerID:productName:YYYY:MM:DD:HH, got %s", template)
	}

	key = Key{PartitionKey: "123:repo:123:2024:3:18:9"}
	template = key.GetPartitionTemplate()

	if template != "customerID:repo:repoID:YYYY:MM:DD:HH" {
		t.Errorf("expected template to be customerID:repo:repoID:YYYY:MM:DD:HH, got %s", template)
	}

	key = Key{PartitionKey: "123:org:123:2024:3:18:9:byOrgAndRepo"}
	template = key.GetPartitionTemplate()

	if template != "customerID:org:orgID:YYYY:MM:DD:HH:byOrgAndRepo" {
		t.Errorf("expected template to be customerID:org:orgID:YYYY:MM:DD:HH:byOrgAndRepo, got %s", template)
	}

	key = Key{PartitionKey: "customer:123:discounts"}
	template = key.GetPartitionTemplate()

	if template != "customer:customerID:discounts" {
		t.Errorf("expected template to be customer:customerID:discounts, got %s", template)
	}
}
