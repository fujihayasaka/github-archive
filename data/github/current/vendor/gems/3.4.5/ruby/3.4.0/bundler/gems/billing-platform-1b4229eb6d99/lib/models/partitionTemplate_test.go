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
	tests := []struct {
		partitionKey string
		expected     string
	}{
		{"123:actions_linux:2024:3:18:9", "customerID:skuName:YYYY:MM:DD:HH"},
		{"123:actions:2024:3:18:9", "customerID:productName:YYYY:MM:DD:HH"},
		{"123:repo:123:2024:3:18:9", "customerID:repo:repoID:YYYY:MM:DD:HH"},
		{"123:org:123:2024:3:18:9:byOrgAndRepo", "customerID:org:orgID:YYYY:MM:DD:HH:byOrgAndRepo"},
		{"customer:123:discounts", "customer:customerID:discounts"},
		{"2025:01:25:byAzureEmission", "YYYY:MM:DD:byAzureEmission"},
		{"customer:12345", "customer:customerID"},
		{"customer:12345:costCenters", "customer:customerID:costCenters"},
		{"invoices:active:2023:7", "invoices:active:YYYY:MM"},
		{"invoices:submitted:2023:7", "invoices:submitted:YYYY:MM"},
		{"actions", "productName"},
		{"1061737:2024:8:topOrgs", "customerID:YYYY:MM:topOrgs"},
		{"customer:1061737:usageReportExports:completed", "customer:customerID:usageReportExports:completed"},
		{"active:actions_storage:events", "active:skuName:events"},
		{"1061737:actions_storage:events:rollup", "customerID:skuName:events:rollup"},
		{"1061737:copilot_for_business:events", "customerID:skuName:events"},
		{"packages_storage:2024:9:1:byZuoraEmission", "skuName:YYYY:MM:DD:byZuoraEmission"},
	}

	for _, tt := range tests {
		t.Run(tt.partitionKey, func(t *testing.T) {
			key := Key{PartitionKey: tt.partitionKey}
			template := key.GetPartitionTemplate()
			if template != tt.expected {
				t.Errorf("expected template to be %s, got %s", tt.expected, template)
			}
		})
	}
}
