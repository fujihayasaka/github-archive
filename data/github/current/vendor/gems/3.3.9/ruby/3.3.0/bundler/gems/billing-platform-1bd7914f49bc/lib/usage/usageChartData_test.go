package usage

import (
	"context"
	"testing"
	"time"

	"github.com/github/billing-platform/lib/engines"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/billing-platform/lib/twirp/proto"
	"github.com/github/github-telemetry-go/log"

	// "github.com/github/billing-platform/testing/helpers"
	"github.com/stretchr/testify/assert"
)

func Test_getGroupString(t *testing.T) {
	item := &models.UsageItem{
		UsageEntityId:         "123",
		Product:               "product1",
		Sku:                   "sku1",
		UsageAt:               1722378113028,
		GrossAmount:           100.0,
		DiscountAmount:        10.0,
		NetAmount:             90.0,
		FriendlySkuName:       "friendlySkuName",
		RepoId:                12,
		OrgId:                 10,
		DiscountDataAvailable: true,
	}

	tests := []struct {
		name     string
		groupBy  proto.UsageGroupBy
		expected string
	}{
		{"NoGroupBy", proto.UsageGroupBy_NoGroupBy, "Usage"},
		{"GroupByProduct", proto.UsageGroupBy_GroupByProduct, "product1"},
		{"GroupBySku", proto.UsageGroupBy_GroupBySku, "friendlySkuName"},
		{"GroupByOrganization", proto.UsageGroupBy_GroupByOrganization, "10"},
		{"GroupByRepository", proto.UsageGroupBy_GroupByRepository, "12"},
		{"GroupByOrgRepoProductSku", proto.UsageGroupBy_GroupByOrgRepoProductSku, "10-12-product1-sku1"},
		{"GroupByCostCenter", proto.UsageGroupBy_GroupByCostCenter, "123"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			groupString := getGroupString(tt.groupBy, item)
			assert.Equal(t, tt.expected, groupString)
		})
	}
}

func Test_getUsageTimestamp(t *testing.T) {
	timestamp := int64(1722378113028)

	tests := []struct {
		name     string
		period   proto.BillingPeriod
		expected string
	}{
		{"Hourly", proto.BillingPeriod_Hourly, "2024-07-30 22:21:00 +0000 UTC"},
		{"Daily", proto.BillingPeriod_Daily, "2024-07-30 22:00:00 +0000 UTC"},
		{"Monthly", proto.BillingPeriod_Monthly, "2024-07-30 00:00:00 +0000 UTC"},
		{"Yearly", proto.BillingPeriod_Yearly, "2024-07-01 00:00:00 +0000 UTC"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			timestamp := getUsageTimestamp(timestamp, tt.period)
			assert.Equal(t, tt.expected, timestamp)
		})
	}
}

func Test_getUsageItems(t *testing.T) {
	item := &models.UsageItem{
		UsageEntityId:         "123",
		Product:               "product1",
		Sku:                   "sku1",
		UsageAt:               1722378113028,
		GrossAmount:           100.0,
		DiscountAmount:        10.0,
		NetAmount:             90.0,
		FriendlySkuName:       "friendlySkuName",
		RepoId:                12,
		OrgId:                 10,
		DiscountDataAvailable: true,
	}

	itemsHourly := map[string]*UsageChartItem{
		"2024-07-30 22:21:00 +0000 UTC": {
			totalAmount:    90,
			billedAmount:   100,
			usageAt:        1722378113028,
			discountAmount: 10,
		},
	}

	itemsDaily := map[string]*UsageChartItem{
		"2024-07-30 22:00:00 +0000 UTC": {
			totalAmount:    90,
			billedAmount:   100,
			usageAt:        1722378113028,
			discountAmount: 10,
		},
	}

	itemsMonthly := map[string]*UsageChartItem{
		"2024-07-30 00:00:00 +0000 UTC": {
			totalAmount:    90,
			billedAmount:   100,
			usageAt:        1722378113028,
			discountAmount: 10,
		},
	}

	itemsYearly := map[string]*UsageChartItem{
		"2024-07-01 00:00:00 +0000 UTC": {
			totalAmount:    90,
			billedAmount:   100,
			usageAt:        1722378113028,
			discountAmount: 10,
		},
	}

	tests := []struct {
		name                   string
		item                   *models.UsageItem
		period                 proto.BillingPeriod
		totalAmount            float64
		existingItems          map[string]*UsageChartItem
		expectedFirstNetAmount float64
		expectedFirstItem      string
		expectedTotalAmount    float64
		expectedLength         int
	}{
		{"Hourly_EmptyArray", item, proto.BillingPeriod_Hourly, 0, make(map[string]*UsageChartItem), 90, "2024-07-30 22:21:00 +0000 UTC", 90, 1},
		{"Daily_EmptyArray", item, proto.BillingPeriod_Daily, 0, make(map[string]*UsageChartItem), 90, "2024-07-30 22:00:00 +0000 UTC", 90, 1},
		{"Monthly_EmptyArray", item, proto.BillingPeriod_Monthly, 0, make(map[string]*UsageChartItem), 90, "2024-07-30 00:00:00 +0000 UTC", 90, 1},
		{"Yearly_EmptyArray", item, proto.BillingPeriod_Yearly, 0, make(map[string]*UsageChartItem), 90, "2024-07-01 00:00:00 +0000 UTC", 90, 1},
		{"Hourly_ExistingItems", item, proto.BillingPeriod_Hourly, 20, itemsHourly, 180, "2024-07-30 22:21:00 +0000 UTC", 110, 1},
		{"Daily_ExistingItems", item, proto.BillingPeriod_Daily, 30, itemsDaily, 180, "2024-07-30 22:00:00 +0000 UTC", 120, 1},
		{"Monthly_ExistingItems", item, proto.BillingPeriod_Monthly, 40, itemsMonthly, 180, "2024-07-30 00:00:00 +0000 UTC", 130, 1},
		{"Yearly_ExistingItems", item, proto.BillingPeriod_Yearly, 50, itemsYearly, 180, "2024-07-01 00:00:00 +0000 UTC", 140, 1},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			usageMap, totalAmount := getUsageItems(tt.item, tt.period, tt.existingItems, tt.totalAmount)
			assert.Equal(t, tt.expectedFirstNetAmount, usageMap[tt.expectedFirstItem].totalAmount)
			assert.Equal(t, tt.expectedTotalAmount, totalAmount)
			assert.Equal(t, tt.expectedLength, len(usageMap))
		})
	}
}

func Test_shouldSkipIncludingUsage(t *testing.T) {
	tests := []struct {
		name           string
		groupBy        proto.UsageGroupBy
		groupByString  string
		expectedResult bool
	}{
		{"RepoNoRepoUsage_true", proto.UsageGroupBy_GroupByRepository, "0", true},
		{"RepoRepoUsage_false", proto.UsageGroupBy_GroupByRepository, "1234", false},
		{"OrganizationNoOrgUsage_true", proto.UsageGroupBy_GroupByOrganization, "0", true},
		{"OrganizationOrgUsage_false", proto.UsageGroupBy_GroupByOrganization, "1234", false},
		{"NonRepoGroupBy_false", proto.UsageGroupBy_GroupByProduct, "0", false},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := shouldSkipIncludingUsage(tt.groupBy, tt.groupByString)
			assert.Equal(t, tt.expectedResult, result)
		})
	}

}

func Test_convertCostcenterIdToName(t *testing.T) {
	inputUsageMap := map[string]*UsageMap{"costcenter-uuid-1": {name: "costcenter-uuid-1", totalAmount: 10}, "costcenter-uuid-2": {name: "costcenter-uuid-2", totalAmount: 20}, "costcenter-uuid-3": {name: "costcenter-uuid-3", totalAmount: 30}}
	expectedUsageMap := map[string]*UsageMap{"Cost Center 1": {name: "Cost Center 1", totalAmount: 10}, "Cost Center 2": {name: "Cost Center 2", totalAmount: 20}, "Cost Center 3": {name: "Cost Center 3", totalAmount: 30}}

	tests := []struct {
		name               string
		costCenterUsageMap map[string]*UsageMap
		costCenters        []*models.CostCenter
		convertedUsageMap  map[string]*UsageMap
	}{
		{"Empty Data", make(map[string]*UsageMap, 0), make([]*models.CostCenter, 0), make(map[string]*UsageMap, 0)},
		{"No Costcenter data", map[string]*UsageMap{"costcenter-uuid-1": {name: "costcenter-uuid-1", totalAmount: 10}}, make([]*models.CostCenter, 0), map[string]*UsageMap{"costcenter-uuid-1": {name: "costcenter-uuid-1", totalAmount: 10}}},
		{"With Usage", inputUsageMap,
			[]*models.CostCenter{
				{CostCenterKey: &models.CostCenterKey{Key: &models.Key{PartitionKey: "cc:1", Id: "costcenter-uuid-1"}, UUID: "costcenter-uuid-1"}, Name: "Cost Center 1"},
				{CostCenterKey: &models.CostCenterKey{Key: &models.Key{PartitionKey: "cc:2", Id: "costcenter-uuid-1"}, UUID: "costcenter-uuid-2"}, Name: "Cost Center 2"},
				{CostCenterKey: &models.CostCenterKey{Key: &models.Key{PartitionKey: "cc:3", Id: "costcenter-uuid-1"}, UUID: "costcenter-uuid-3"}, Name: "Cost Center 3"},
			},
			expectedUsageMap,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			convertCostcenterIdToName(tt.costCenterUsageMap, tt.costCenters)
			assert.Equal(t, tt.convertedUsageMap, tt.costCenterUsageMap)
		})
	}
}

func Test_limitTopN(t *testing.T) {
	smallUsageMap := map[string]*UsageMap{
		"1": {totalAmount: 10},
		"2": {totalAmount: 20},
		"3": {totalAmount: 30},
		"4": {totalAmount: 40},
	}

	largeUsageMap := map[string]*UsageMap{
		"1": {totalAmount: 10},
		"2": {totalAmount: 20},
		"3": {totalAmount: 30},
		"4": {totalAmount: 40},
		"5": {totalAmount: 50},
		"6": {totalAmount: 60},
		"7": {totalAmount: 70},
	}

	emptyTopResourceIDs := make([]int64, 0)
	topResourceIDs := []int64{1, 2, 3}

	tests := []struct {
		name                  string
		groupBy               proto.UsageGroupBy
		usageMap              map[string]*UsageMap
		expectedLength        int
		shouldContainAllOther bool
		expectedAllOtherValue float64
		topResourceIDs        []int64
	}{
		{"NoGroupBy_SmallMap", proto.UsageGroupBy_NoGroupBy, smallUsageMap, 4, false, 0, emptyTopResourceIDs},
		{"GroupByProduct_SmallMap", proto.UsageGroupBy_GroupByProduct, smallUsageMap, 4, false, 0, emptyTopResourceIDs},
		{"GroupBySku_SmallMap", proto.UsageGroupBy_GroupBySku, smallUsageMap, 4, false, 0, emptyTopResourceIDs},
		{"GroupByOrganization_SmallMap", proto.UsageGroupBy_GroupByOrganization, smallUsageMap, 4, false, 0, emptyTopResourceIDs},
		{"GroupByRepository_SmallMap", proto.UsageGroupBy_GroupByRepository, smallUsageMap, 4, false, 0, emptyTopResourceIDs},
		{"GroupByOrgRepoProductSku_SmallMap", proto.UsageGroupBy_GroupByOrgRepoProductSku, smallUsageMap, 4, false, 0, emptyTopResourceIDs},
		{"GroupByCostCenter_SmallMap", proto.UsageGroupBy_GroupByCostCenter, smallUsageMap, 4, false, 0, emptyTopResourceIDs},
		{"NoGroupBy_LargeMap", proto.UsageGroupBy_NoGroupBy, largeUsageMap, 7, false, 0, emptyTopResourceIDs},
		{"GroupByProduct_LargeMap", proto.UsageGroupBy_GroupByProduct, largeUsageMap, 7, false, 0, emptyTopResourceIDs},
		{"GroupBySku_LargeMap", proto.UsageGroupBy_GroupBySku, largeUsageMap, 6, true, 30, emptyTopResourceIDs},
		{"GroupByOrganization_LargeMap", proto.UsageGroupBy_GroupByOrganization, largeUsageMap, 6, true, 30, emptyTopResourceIDs},
		{"GroupByRepository_LargeMap", proto.UsageGroupBy_GroupByRepository, largeUsageMap, 6, true, 30, emptyTopResourceIDs},
		{"GroupByOrgRepoProductSku_LargeMap", proto.UsageGroupBy_GroupByOrgRepoProductSku, largeUsageMap, 7, false, 0, emptyTopResourceIDs},
		{"GroupByCostCenter_LargeMap", proto.UsageGroupBy_GroupByCostCenter, largeUsageMap, 6, true, 30, emptyTopResourceIDs},
		{"GroupByOrganization_TopResourceIds", proto.UsageGroupBy_GroupByOrganization, largeUsageMap, 4, true, 220, topResourceIDs},
		{"GroupByRepository_TopResourceIds", proto.UsageGroupBy_GroupByRepository, largeUsageMap, 4, true, 220, topResourceIDs},
		{"GroupBySku_TopResourceIds", proto.UsageGroupBy_GroupBySku, largeUsageMap, 6, true, 30, topResourceIDs},
		{"GroupByOrganization_TopResourceIds_SmallMap", proto.UsageGroupBy_GroupByOrganization, smallUsageMap, 4, false, 0, topResourceIDs},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			limitedUsageMap := limitToTopN(tt.groupBy, tt.usageMap, tt.topResourceIDs)
			assert.Equal(t, tt.expectedLength, len(limitedUsageMap))
			if tt.shouldContainAllOther {
				assert.Equal(t, tt.expectedAllOtherValue, limitedUsageMap["All other"].totalAmount)
			}
		})
	}
}

func Test_addUsageToAllOtherUsageInMap(t *testing.T) {
	usageMap := map[string]*UsageMap{
		"1": {totalAmount: 10},
		"2": {totalAmount: 20},
		"3": {totalAmount: 30},
		"4": {totalAmount: 40},
	}

	usage := &UsageMap{totalAmount: 50}
	expectedAmount := float64(50)

	limitedUsageMap := addUsageToAllOtherUsageInMap(usage, usageMap)
	assert.Equal(t, expectedAmount, limitedUsageMap[allOther].totalAmount)
}

func Test_mergeUsageItems(t *testing.T) {
	items1 := map[string]*UsageChartItem{
		"1": {totalAmount: 10},
		"2": {totalAmount: 20},
		"3": {totalAmount: 30},
		"4": {totalAmount: 40},
		"5": {totalAmount: 50},
	}

	items2 := map[string]*UsageChartItem{
		"1": {totalAmount: 10},
		"2": {totalAmount: 20},
		"3": {totalAmount: 30},
		"4": {totalAmount: 40},
		"6": {totalAmount: 60},
	}

	mergedItems := mergeUsageItems(items1, items2)
	assert.Equal(t, 6, len(mergedItems))
	assert.Equal(t, float64(20), mergedItems["1"].totalAmount)
	assert.Equal(t, float64(40), mergedItems["2"].totalAmount)
	assert.Equal(t, float64(60), mergedItems["3"].totalAmount)
	assert.Equal(t, float64(80), mergedItems["4"].totalAmount)
	assert.Equal(t, float64(60), mergedItems["6"].totalAmount)
	assert.Equal(t, float64(50), mergedItems["5"].totalAmount)
}

func Test_findBillingPeriodRequestType(t *testing.T) {
	tests := []struct {
		name     string
		year     int
		month    int
		day      int
		period   proto.BillingPeriod
		time     time.Time
		expected string
	}{
		{"ThisHour", 2024, 7, 30, proto.BillingPeriod_Hourly, time.Date(2024, 7, 30, 22, 21, 0, 0, time.UTC), "this_hour"},
		{"ThisDay", 2024, 7, 30, proto.BillingPeriod_Daily, time.Date(2024, 7, 30, 22, 21, 0, 0, time.UTC), "today"},
		{"ThisMonth", 2024, 7, 1, proto.BillingPeriod_Monthly, time.Date(2024, 7, 30, 22, 21, 0, 0, time.UTC), "this_month"},
		{"ThisYear", 2024, 1, 1, proto.BillingPeriod_Yearly, time.Date(2024, 7, 30, 22, 21, 0, 0, time.UTC), "this_year"},
		{"LastMonth", 2024, 6, 1, proto.BillingPeriod_Monthly, time.Date(2024, 7, 30, 22, 21, 0, 0, time.UTC), "last_month"},
		{"LastYear", 2023, 1, 1, proto.BillingPeriod_Yearly, time.Date(2024, 7, 30, 22, 21, 0, 0, time.UTC), "last_year"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			requestType := findBillingPeriodRequestType(tt.year, tt.month, tt.day, tt.period, tt.time)
			assert.Equal(t, tt.expected, requestType)
		})
	}
}

func Test_generateBlankThisHourDatasets(t *testing.T) {
	tests := []struct {
		name                   string
		time                   time.Time
		size                   int
		expectedSize           int
		expectedSizeOfDatasets int
	}{
		{"3Datasets22Minutes", time.Date(2024, 7, 30, 22, 22, 0, 0, time.UTC), 3, 3, 22},
		{"1Datasets5Minutes", time.Date(2024, 7, 30, 22, 5, 0, 0, time.UTC), 1, 1, 5},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			datasets := generateBlankDatasets(tt.time, tt.size, "this_hour")
			assert.Equal(t, tt.expectedSize, len(datasets))
			assert.Equal(t, tt.expectedSizeOfDatasets, len(datasets[0].Data))
		})
	}
}

func Test_generateBlankTodayDatasets(t *testing.T) {
	tests := []struct {
		name                   string
		time                   time.Time
		size                   int
		expectedSize           int
		expectedSizeOfDatasets int
	}{
		{"3Datasets20Hours", time.Date(2024, 7, 30, 20, 22, 0, 0, time.UTC), 3, 3, 20},
		{"1Datasets5Hours", time.Date(2024, 7, 30, 5, 5, 0, 0, time.UTC), 1, 1, 5},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			datasets := generateBlankDatasets(tt.time, tt.size, "today")
			assert.Equal(t, tt.expectedSize, len(datasets))
			assert.Equal(t, tt.expectedSizeOfDatasets, len(datasets[0].Data))
		})
	}
}

func Test_generateBlankThisMonthDatasets(t *testing.T) {
	tests := []struct {
		name                   string
		time                   time.Time
		size                   int
		expectedSize           int
		expectedSizeOfDatasets int
	}{
		{"3Datasets20Days", time.Date(2024, 7, 20, 20, 22, 0, 0, time.UTC), 3, 3, 20},
		{"1Datasets5Days", time.Date(2024, 7, 5, 5, 5, 0, 0, time.UTC), 1, 1, 5},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			datasets := generateBlankDatasets(tt.time, tt.size, "this_month")
			assert.Equal(t, tt.expectedSize, len(datasets))
			assert.Equal(t, tt.expectedSizeOfDatasets, len(datasets[0].Data))
		})
	}
}

func Test_generateBlankLastMonthDatasets(t *testing.T) {
	tests := []struct {
		name                   string
		time                   time.Time
		size                   int
		expectedSize           int
		expectedSizeOfDatasets int
	}{
		{"3Datasets31Days", time.Date(2024, 6, 20, 20, 22, 0, 0, time.UTC), 3, 3, 31},
		{"1Datasets30Days", time.Date(2024, 5, 5, 5, 5, 0, 0, time.UTC), 1, 1, 30},
		{"2Datasets31DaysJanuary", time.Date(2024, 1, 5, 5, 5, 0, 0, time.UTC), 2, 2, 31},
		{"2Datasets29DaysLeapYear", time.Date(2024, 3, 5, 5, 5, 0, 0, time.UTC), 2, 2, 29},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			datasets := generateBlankDatasets(tt.time, tt.size, "last_month")
			assert.Equal(t, tt.expectedSize, len(datasets))
			assert.Equal(t, tt.expectedSizeOfDatasets, len(datasets[0].Data))
		})
	}
}

func Test_generateBlankThisYearDatasets(t *testing.T) {
	tests := []struct {
		name                   string
		time                   time.Time
		size                   int
		expectedSize           int
		expectedSizeOfDatasets int
	}{
		{"3Datasets6Months", time.Date(2024, 6, 20, 20, 22, 0, 0, time.UTC), 3, 3, 6},
		{"1Datasets5Months", time.Date(2024, 5, 5, 5, 5, 0, 0, time.UTC), 1, 1, 5},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			datasets := generateBlankDatasets(tt.time, tt.size, "this_year")
			assert.Equal(t, tt.expectedSize, len(datasets))
			assert.Equal(t, tt.expectedSizeOfDatasets, len(datasets[0].Data))
		})
	}
}

func Test_generateBlankLastYearDatasets(t *testing.T) {
	tests := []struct {
		name                   string
		time                   time.Time
		size                   int
		expectedSize           int
		expectedSizeOfDatasets int
	}{
		{"3Datasets12Months", time.Date(2023, 6, 20, 20, 22, 0, 0, time.UTC), 3, 3, 12},
		{"1Datasets12Months", time.Date(2023, 5, 5, 5, 5, 0, 0, time.UTC), 1, 1, 12},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			datasets := generateBlankDatasets(tt.time, tt.size, "last_year")
			assert.Equal(t, tt.expectedSize, len(datasets))
			assert.Equal(t, tt.expectedSizeOfDatasets, len(datasets[0].Data))
		})
	}
}

func Test_fillInDatasetsWithUsageMap(t *testing.T) {
	lastMonthUsageDataActions := map[string]*UsageChartItem{
		"2023-05-01 00:00:00 +0000 UTC": {totalAmount: 90, usageAt: 1682899200, billedAmount: 100, discountAmount: 10},
	}
	lastMonthUsageDataPackages := map[string]*UsageChartItem{
		"2023-05-25 00:00:00 +0000 UTC": {totalAmount: 300, usageAt: 1684195200, billedAmount: 3000, discountAmount: 2700},
	}
	lastMonthUsageDataGhas := map[string]*UsageChartItem{
		"2023-05-30 00:00:00 +0000 UTC": {totalAmount: 10, usageAt: 1685232000, billedAmount: 50, discountAmount: 40},
	}

	lastMonthUsageMap := map[string]*UsageMap{
		"actions":  {name: "actions", totalAmount: 10, data: lastMonthUsageDataActions},
		"packages": {name: "packages", totalAmount: 20, data: lastMonthUsageDataPackages},
		"ghas":     {name: "ghas", totalAmount: 30, data: lastMonthUsageDataGhas},
	}

	tests := []struct {
		name                   string
		dataset                []*proto.UsageChartDataset
		usageMap               map[string]*UsageMap
		period                 proto.BillingPeriod
		expectedSize           int
		expectedSizeOfDatasets int
		expectedStart          int64
		expectedEnd            int64
	}{
		{"LastMonth", generateBlankDatasets(time.Date(2023, 6, 20, 20, 22, 0, 0, time.UTC), len(lastMonthUsageMap), "last_month"), lastMonthUsageMap, proto.BillingPeriod_Monthly, 3, 31, 1682899200000, 1685491200000},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			datasets := fillInDatasetsWithUsageMap(tt.dataset, tt.usageMap, tt.period)
			last := len(datasets[0].Data) - 1
			assert.Equal(t, tt.expectedSize, len(datasets))
			assert.Equal(t, tt.expectedSizeOfDatasets, len(datasets[0].Data))
			assert.Equal(t, float64(0), datasets[0].Data[0].Y)
			assert.Equal(t, float64(3000), datasets[0].Data[25].Y)
			assert.Equal(t, float64(100), datasets[1].Data[1].Y)
			assert.Equal(t, float64(100), datasets[1].Data[24].Y)
			assert.Equal(t, float64(0), datasets[2].Data[0].Y)
			assert.Equal(t, float64(50), datasets[2].Data[30].Y)
			assert.Equal(t, tt.expectedStart, datasets[0].Data[0].X)
			assert.Equal(t, tt.expectedEnd, datasets[0].Data[last].X)
		})
	}
}

func Test_BuildUsageChartData(t *testing.T) {
	now := time.Now().UTC()
	usageLineItems := []engines.PartitionDetailUsageItemResults{
		{
			UsagePartitionDetail: &models.UsagePartitionDetail{
				UsageEntityId: "1",
				UsageTime:     models.NewUsageTime().WithYear(int64(now.Year())).WithMonthInt(int64(now.Month())).WithDay(now.Day()).WithHour(now.Hour()).WithMinute(now.Minute()),
				ActiveType:    models.Monthly,
				GroupBy:       "1",
			},
			UsageItems: []*models.UsageItem{
				{
					UsageEntityId:         "1",
					Product:               "product1",
					Sku:                   "sku1",
					UsageAt:               now.UnixMilli() - 60000,
					GrossAmount:           100.0,
					DiscountAmount:        10.0,
					NetAmount:             90.0,
					FriendlySkuName:       "friendlySkuName",
					RepoId:                12,
					OrgId:                 10,
					DiscountDataAvailable: true,
				},
				{
					UsageEntityId:         "1",
					Product:               "product1",
					Sku:                   "sku1",
					UsageAt:               now.UnixMilli() - 60000,
					GrossAmount:           100.0,
					DiscountAmount:        10.0,
					NetAmount:             90.0,
					FriendlySkuName:       "friendlySkuName",
					RepoId:                12,
					OrgId:                 10,
					DiscountDataAvailable: true,
				},
			},
		},
		{
			UsagePartitionDetail: &models.UsagePartitionDetail{
				UsageEntityId: "CostCenterA",
				UsageTime:     models.NewUsageTime().WithYear(int64(now.Year())).WithMonthInt(int64(now.Month())).WithDay(now.Day()).WithHour(now.Hour()).WithMinute(now.Minute()),
				ActiveType:    models.Monthly,
				GroupBy:       "1",
			},
			UsageItems: []*models.UsageItem{
				{
					UsageEntityId:         "1",
					Product:               "product2",
					Sku:                   "sku1",
					UsageAt:               now.UnixMilli() - 60000,
					GrossAmount:           100.0,
					DiscountAmount:        10.0,
					NetAmount:             90.0,
					FriendlySkuName:       "friendlySkuName",
					RepoId:                12,
					OrgId:                 10,
					DiscountDataAvailable: true,
				},
				{
					UsageEntityId:         "1",
					Product:               "product1",
					Sku:                   "sku1",
					UsageAt:               now.UnixMilli() - 60000,
					GrossAmount:           100.0,
					DiscountAmount:        10.0,
					NetAmount:             90.0,
					FriendlySkuName:       "friendlySkuName",
					RepoId:                12,
					OrgId:                 10,
					DiscountDataAvailable: true,
				},
			},
		},
	}

	input := &proto.GetUsageChartDataRequest{
		UsageEntityId: "1",
		Year:          int64(now.Year()),
		Month:         int64(now.Month()),
		Day:           int64(now.Day()),
		Hour:          int64(now.Hour()),
		BillingPeriod: proto.BillingPeriod_Hourly,
		GroupBy:       proto.UsageGroupBy_GroupByProduct,
	}

	topResourceIDs := []int64{}
	ctx := context.Background()
	logger := log.NewNullLogger()

	tests := []struct {
		name                   string
		expectedSize           int
		expectedSizeOfDatasets int
		product1YValue         float64
		product1DiscountAmount string
		product1GrossAmount    string
		product1TotalAmount    string
		product2YValue         float64
		product2DiscountAmount string
		product2GrossAmount    string
		product2TotalAmount    string
	}{
		{"GenerateChartData", 2, now.Minute(), 300, "$30.00", "$300.00", "$270.00", 100, "$10.00", "$100.00", "$90.00"},
	}

	usageService := &UsageService{}
	costCenters := []*models.CostCenter{}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			chartData := usageService.BuildUsageChartData(ctx, logger, input, usageLineItems, costCenters, topResourceIDs)
			assert.Equal(t, tt.expectedSize, len(chartData))
			assert.Equal(t, tt.expectedSizeOfDatasets, len(chartData[0].Data))
			if now.Minute() > 0 {
				lastIndex := len(chartData[0].Data) - 1
				assert.Equal(t, tt.product1YValue, chartData[0].Data[lastIndex].Y)
				assert.Equal(t, tt.product1DiscountAmount, chartData[0].Data[lastIndex].Custom.DiscountAmount)
				assert.Equal(t, tt.product1GrossAmount, chartData[0].Data[lastIndex].Custom.GrossAmount)
				assert.Equal(t, tt.product1TotalAmount, chartData[0].Data[lastIndex].Custom.TotalAmount)
				assert.Equal(t, tt.product2YValue, chartData[1].Data[lastIndex].Y)
				assert.Equal(t, tt.product2DiscountAmount, chartData[1].Data[lastIndex].Custom.DiscountAmount)
				assert.Equal(t, tt.product2GrossAmount, chartData[1].Data[lastIndex].Custom.GrossAmount)
				assert.Equal(t, tt.product2TotalAmount, chartData[1].Data[lastIndex].Custom.TotalAmount)
			}
		})
	}
}
