package models

import (
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
)

func Test_UsagePartitionDetail_ToPartitionKey_ForCustomer(t *testing.T) {
	usageDetail := &UsagePartitionDetail{
		UsageEntityId: "35",
		Product:       "",
		Sku:           "",
		RepoId:        0,
		UsageTime:     NewUsageTimeFromTime(time.Date(2011, 11, 14, 3, 0, 0, 0, time.UTC)),
		ActiveType:    Hourly,
	}

	partitionKey := usageDetail.ToPartitionKey()
	expectedKey := "35:2011:11:14:3"

	if partitionKey != expectedKey {
		t.Errorf("Expected partition key to be %s, got %s", expectedKey, partitionKey)
	}
}

func Test_UsagePartitionDetail_ToPartitionKey_ForRepo(t *testing.T) {
	usageDetail := &UsagePartitionDetail{
		UsageEntityId: "45",
		Product:       "",
		Sku:           "",
		RepoId:        187,
		UsageTime:     NewUsageTimeFromTime(time.Date(2011, 11, 14, 3, 0, 0, 0, time.UTC)),
		ActiveType:    Hourly,
	}

	partitionKey := usageDetail.ToRepoPartitionKey()
	expectedKey := "45:repo:187:2011:11:14:3"

	if partitionKey != expectedKey {
		t.Errorf("Expected partition key to be %s, got %s", expectedKey, partitionKey)
	}
}

func Test_UsagePartitionDetail_ToGetDiscountsPartitionKey(t *testing.T) {
	tests := []struct {
		name                 string
		upd                  *UsagePartitionDetail
		expectedPartitionKey string
	}{
		{
			name: "appends discount suffix to the partition key",
			upd: &UsagePartitionDetail{
				UsageEntityId: "55",
				Product:       "",
				Sku:           "",
				UsageTime:     NewUsageTimeFromTime(time.Date(2011, 11, 14, 3, 0, 0, 0, time.UTC)),
				ActiveType:    Hourly,
			},
			expectedPartitionKey: "55:2011:11:14:3:discount",
		},
		{
			name: "includes sku name if present",
			upd: &UsagePartitionDetail{
				UsageEntityId: "55",
				Product:       "",
				Sku:           "actions_linux",
				UsageTime:     NewUsageTimeFromTime(time.Date(2011, 11, 14, 3, 0, 0, 0, time.UTC)),
				ActiveType:    Hourly,
			},
			expectedPartitionKey: "55:actions_linux:2011:11:14:3:discount",
		},
		{
			name: "includes org id if present",
			upd: &UsagePartitionDetail{
				UsageEntityId: "55",
				UsageTime:     NewUsageTimeFromTime(time.Date(2011, 11, 14, 3, 0, 0, 0, time.UTC)),
				ActiveType:    Hourly,
				OrgId:         123,
			},
			expectedPartitionKey: "55:org:123:2011:11:14:3:byProductSku:discount",
		},
		{
			name: "includes repo id if present",
			upd: &UsagePartitionDetail{
				UsageEntityId: "55",
				UsageTime:     NewUsageTimeFromTime(time.Date(2011, 11, 14, 3, 0, 0, 0, time.UTC)),
				ActiveType:    Hourly,
				RepoId:        123,
			},
			expectedPartitionKey: "55:repo:123:2011:11:14:3:byProductSku:discount",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			assert.Equal(t, tt.expectedPartitionKey, tt.upd.ToDiscountsPartitionKey())
		})
	}
}

func Test_UsagePartitionDetail_ToGetLineItemsPartitionKey(t *testing.T) {
	tests := []struct {
		name                 string
		upd                  *UsagePartitionDetail
		expectedPartitionKey string
	}{
		{
			name: "hits the org byProductSku partition when not grouping for org queries",
			upd: &UsagePartitionDetail{
				UsageEntityId: "55",
				Product:       "",
				Sku:           "",
				RepoId:        0,
				OrgId:         333,
				UsageTime:     NewUsageTimeFromTime(time.Date(2011, 11, 14, 3, 0, 0, 0, time.UTC)),
				ActiveType:    Hourly,
			},
			expectedPartitionKey: "55:org:333:2011:11:14:3:byProductSku",
		},
		{
			name: "hits the repo byProductSku partition when not grouping for repo queries",
			upd: &UsagePartitionDetail{
				UsageEntityId: "55",
				Product:       "",
				Sku:           "",
				RepoId:        333,
				OrgId:         0,
				UsageTime:     NewUsageTimeFromTime(time.Date(2011, 11, 14, 3, 0, 0, 0, time.UTC)),
				ActiveType:    Hourly,
			},
			expectedPartitionKey: "55:repo:333:2011:11:14:3:byProductSku",
		},
		{
			name: "hits the repo byProductSku partition when grouping by product or SKU for repo queries",
			upd: &UsagePartitionDetail{
				UsageEntityId: "55",
				Product:       "",
				Sku:           "",
				RepoId:        333,
				OrgId:         0,
				UsageTime:     NewUsageTimeFromTime(time.Date(2011, 11, 14, 3, 0, 0, 0, time.UTC)),
				ActiveType:    Hourly,
				GroupBy:       "byProductSku",
			},
			expectedPartitionKey: "55:repo:333:2011:11:14:3:byProductSku",
		},
		{
			name: "hits the org byProductSku partition when grouping by product or SKU for org queries",
			upd: &UsagePartitionDetail{
				UsageEntityId: "55",
				Product:       "",
				Sku:           "",
				RepoId:        0,
				OrgId:         333,
				UsageTime:     NewUsageTimeFromTime(time.Date(2011, 11, 14, 3, 0, 0, 0, time.UTC)),
				ActiveType:    Hourly,
				GroupBy:       "byProductSku",
			},
			expectedPartitionKey: "55:org:333:2011:11:14:3:byProductSku",
		},
		{
			name: "hits the byOrgAndRepo partition when grouping by org or repo",
			upd: &UsagePartitionDetail{
				UsageEntityId: "55",
				Product:       "",
				Sku:           "",
				RepoId:        0,
				OrgId:         0,
				UsageTime:     NewUsageTimeFromTime(time.Date(2011, 11, 14, 3, 0, 0, 0, time.UTC)),
				ActiveType:    Hourly,
				GroupBy:       "byOrgAndRepo",
			},
			expectedPartitionKey: "55:2011:11:14:3:byOrgAndRepo",
		},
		{
			name: "hits the byOrgRepoProductSku partition when grouping by orgRepoProductSku",
			upd: &UsagePartitionDetail{
				UsageEntityId: "55",
				Product:       "",
				Sku:           "",
				RepoId:        0,
				OrgId:         0,
				UsageTime:     NewUsageTimeFromTime(time.Date(2011, 11, 14, 3, 0, 0, 0, time.UTC)),
				ActiveType:    Hourly,
				GroupBy:       "byOrgRepoProductSku",
			},
			expectedPartitionKey: "55:2011:11:14:3:byOrgRepoProductSku",
		},
		{
			name: "hits the org byProductSku partition when grouping by cost center for org queries",
			upd: &UsagePartitionDetail{
				UsageEntityId: "55",
				Product:       "",
				Sku:           "",
				RepoId:        0,
				OrgId:         333,
				UsageTime:     NewUsageTimeFromTime(time.Date(2011, 11, 14, 3, 0, 0, 0, time.UTC)),
				ActiveType:    Hourly,
				GroupBy:       "byCostCenter",
			},
			expectedPartitionKey: "55:org:333:2011:11:14:3:byProductSku",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			assert.Equal(t, tt.expectedPartitionKey, tt.upd.ToGetLineItemsPartitionKey())
		})
	}
}

func Test_UsagePartitionDetail_ToDiscountsPartitionKey_WithProduct(t *testing.T) {
	usageDetail := &UsagePartitionDetail{
		UsageEntityId: "55",
		Product:       "actions",
		UsageTime:     NewUsageTimeFromTime(time.Date(2011, 11, 14, 3, 0, 0, 0, time.UTC)),
		ActiveType:    Daily,
	}

	partitionKey := usageDetail.ToDiscountsPartitionKey()
	expectedKey := "55:2011:11:14:discount"

	if partitionKey != expectedKey {
		t.Errorf("Expected partition key to be %s, got %s", expectedKey, partitionKey)
	}
}

func Test_UsagePartitionDetail_HasSearchFilters(t *testing.T) {
	tests := []struct {
		name     string
		upd      *UsagePartitionDetail
		expected bool
	}{
		{
			name: "no filters",
			upd: &UsagePartitionDetail{
				Product: "",
				Sku:     "",
				RepoId:  0,
				OrgId:   0,
			},
			expected: false,
		},
		{
			name: "org filter",
			upd: &UsagePartitionDetail{
				Product: "",
				Sku:     "",
				RepoId:  0,
				OrgId:   123,
			},
			expected: true,
		},
		{
			name: "repo filter",
			upd: &UsagePartitionDetail{
				Product: "",
				Sku:     "",
				RepoId:  123,
				OrgId:   0,
			},
			expected: true,
		},
		{
			name: "sku filter",
			upd: &UsagePartitionDetail{
				Product: "",
				Sku:     "actions_linux",
				RepoId:  0,
				OrgId:   0,
			},
			expected: true,
		},
		{
			name: "product filter",
			upd: &UsagePartitionDetail{
				Product: "actions",
				Sku:     "",
				RepoId:  0,
				OrgId:   0,
			},
			expected: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			assert.Equal(t, tt.expected, tt.upd.HasSearchFilters())
		})
	}
}
