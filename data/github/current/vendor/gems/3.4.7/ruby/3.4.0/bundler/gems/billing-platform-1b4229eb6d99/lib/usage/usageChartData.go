package usage

import (
	"context"
	"fmt"
	"math"
	"slices"
	"sort"
	"strconv"
	"time"

	"github.com/github/billing-platform/lib/models"
	"github.com/github/billing-platform/lib/twirp/proto"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
)

type UsageChartItem struct {
	billedAmount   float64
	discountAmount float64
	usageAt        int64
	totalAmount    float64
}

type UsageMap struct {
	name        string
	data        map[string]*UsageChartItem
	totalAmount float64
}

// Request types for billing period
const (
	BillingPeriodRequestTypeThisHour  = "this_hour"
	BillingPeriodRequestTypeToday     = "today"
	BillingPeriodRequestTypeThisMonth = "this_month"
	BillingPeriodRequestTypeThisYear  = "this_year"
	BillingPeriodRequestTypeLastMonth = "last_month"
	BillingPeriodRequestTypeLastYear  = "last_year"
)

// Top N items to show in the usage chart, limits to this number + "All other" usage
const topN = 5
const allOther = "All other"

// List of GroupBys where we restrict the number of items to show in the usage chart
var groupByTopN = []proto.UsageGroupBy{
	proto.UsageGroupBy_GroupByOrganization,
	proto.UsageGroupBy_GroupByRepository,
	proto.UsageGroupBy_GroupByCostCenter,
	proto.UsageGroupBy_GroupBySku,
}

// Takes a list of net usage items and the input request and builds those into the format for a UsageChartDataset
func (u *UsageService) BuildUsageChartData(ctx context.Context, logger log.Logger, input *proto.GetUsageChartDataRequest, usageLineItems []models.PartitionDetailUsageItemResults, costCenters []*models.CostCenter, topResourceIDs []int64) []*proto.UsageChartDataset {
	billingPeriod := input.GetBillingPeriod()
	groupBy := input.GetGroupBy()
	logger.Info("Building usage chart data", kvp.String("billingPeriod", billingPeriod.String()), kvp.String("groupBy", groupBy.String()))

	// Each item in this map will be a dataset, which maps to an individual line in the usage chart
	usageMap := make(map[string]*UsageMap)

	// Group data together into each dataset
	for _, netUsageLineItem := range usageLineItems {
		for _, item := range netUsageLineItem.UsageItems {
			groupByString := getGroupString(groupBy, item)
			if _, ok := usageMap[groupByString]; !ok {
				// Add this new groupByString to the usageMap
				usageMap[groupByString] = &UsageMap{
					name:        groupByString,
					data:        map[string]*UsageChartItem{},
					totalAmount: 0,
				}
			}

			// Add usage items by the groupByString and increment the total amount
			usageItems, totalAmount := getUsageItems(item, billingPeriod, usageMap[groupByString].data, usageMap[groupByString].totalAmount)
			usageMap[groupByString].data = usageItems
			usageMap[groupByString].totalAmount = totalAmount
		}
	}

	// Limit to top N items, if applicable
	usageMap = limitToTopN(groupBy, usageMap, topResourceIDs)

	// if the groupby is by costcenter, replace costcenter id with the name
	if input.GetGroupBy() == proto.UsageGroupBy_GroupByCostCenter {
		convertCostcenterIdToName(usageMap, costCenters)
		convertEnterpriseIdToName(usageMap, input.UsageEntityId)
	}
	// Fill in empty data for each dataset and transform to proto.UsageChartData
	datasets := transformUsageMapToUsageChartDatasets(usageMap, input)

	return datasets
}

func convertCostcenterIdToName(usageMap map[string]*UsageMap, costCenters []*models.CostCenter) {
	if len(costCenters) == 0 || len(usageMap) == 0 {
		return
	}
	AllCostCenterIdToName := make(map[string]string)
	UsageCostCenterIdToName := make(map[string]string)

	for _, costCenter := range costCenters {
		AllCostCenterIdToName[costCenter.UUID] = costCenter.Name
	}

	// Add "Enterprise Only" to the map for usage items that don't have a cost center
	// AllCostCenterIdToName[costCenters[0].Customer.EnterpriseCustomerId] = "Enterprise Only"

	for costCenterId := range usageMap {

		if name, exists := AllCostCenterIdToName[costCenterId]; exists {
			UsageCostCenterIdToName[costCenterId] = name
		}

	}

	for id, name := range UsageCostCenterIdToName {
		usageMap[name] = usageMap[id]
		usageMap[name].name = name
		delete(usageMap, id)
	}
}

func convertEnterpriseIdToName(usageMap map[string]*UsageMap, enterpriseId string) {

	if enterpriseOnlyUsage, exists := usageMap[enterpriseId]; exists {
		enterpriseOnlyUsage.name = "Enterprise Only"
		usageMap["Enterprise Only"] = enterpriseOnlyUsage
		delete(usageMap, enterpriseId)
	}
}

func getGroupString(groupBy proto.UsageGroupBy, item *models.UsageItem) string {
	switch groupBy {
	case proto.UsageGroupBy_GroupByOrganization:
		return fmt.Sprintf("%d", item.OrgId)
	case proto.UsageGroupBy_GroupByRepository:
		return fmt.Sprintf("%d", item.RepoId)
	case proto.UsageGroupBy_GroupByCostCenter:
		return item.UsageEntityId
	case proto.UsageGroupBy_GroupByProduct:
		return item.Product
	case proto.UsageGroupBy_GroupBySku:
		return item.FriendlySkuName
	case proto.UsageGroupBy_NoGroupBy:
		return "Usage"
	case proto.UsageGroupBy_GroupByOrgRepoProductSku:
		return fmt.Sprintf("%d-%d-%s-%s", item.OrgId, item.RepoId, item.Product, item.Sku)
	default:
		return ""
	}
}

func getUsageTimestamp(timestamp int64, billingPeriod proto.BillingPeriod) string {
	switch billingPeriod {
	case proto.BillingPeriod_Hourly:
		return time.UnixMilli(timestamp).UTC().Truncate(time.Minute).String()
	case proto.BillingPeriod_Daily:
		return time.UnixMilli(timestamp).UTC().Truncate(time.Hour).String()
	case proto.BillingPeriod_Monthly:
		return time.UnixMilli(timestamp).UTC().Truncate(time.Hour * 24).String()
	case proto.BillingPeriod_Yearly:
		timeFromTimestamp := time.UnixMilli(timestamp).UTC()
		return time.Date(timeFromTimestamp.Year(), timeFromTimestamp.Month(), 1, 0, 0, 0, 0, time.UTC).String()
	default:
		return time.UnixMilli(timestamp).UTC().String()
	}
}

func getUsageItems(usageItem *models.UsageItem, billingPeriod proto.BillingPeriod, usageData map[string]*UsageChartItem, totalAmount float64) (map[string]*UsageChartItem, float64) {
	usageAt := getUsageTimestamp(usageItem.UsageAt, billingPeriod)
	if _, ok := usageData[usageAt]; !ok {
		usageData[usageAt] = &UsageChartItem{
			billedAmount:   usageItem.GrossAmount,
			discountAmount: usageItem.DiscountAmount,
			usageAt:        usageItem.UsageAt,
			totalAmount:    usageItem.NetAmount,
		}
	} else {
		usageData[usageAt].billedAmount += usageItem.GrossAmount
		usageData[usageAt].discountAmount += usageItem.DiscountAmount
		usageData[usageAt].totalAmount += usageItem.NetAmount
	}
	totalAmount += usageItem.NetAmount
	return usageData, totalAmount
}

func limitToTopN(groupBy proto.UsageGroupBy, usageMap map[string]*UsageMap, topResourceIDs []int64) map[string]*UsageMap {
	// Return early if groupBy is not in groupByTopN list
	if !slices.Contains(groupByTopN, groupBy) {
		return usageMap
	}

	// Return early if total number of datasets is less than or equal to topN
	if len(usageMap) <= topN {
		return usageMap
	}

	limitedUsageMap := make(map[string]*UsageMap, 0)
	if len(topResourceIDs) > 0 && (groupBy == proto.UsageGroupBy_GroupByOrganization || groupBy == proto.UsageGroupBy_GroupByRepository) {
		// We have a list of the topResourceIds and are grouping by either org or repository, limit using those instead of trying to find the them
		for groupByString, data := range usageMap {
			resourceId, err := strconv.ParseInt(groupByString, 10, 64)
			if err != nil {
				// If we can't parse the groupByString, add it to all other usage
				limitedUsageMap = addUsageToAllOtherUsageInMap(data, limitedUsageMap)
				continue
			}

			if slices.Contains(topResourceIDs, int64(resourceId)) {
				limitedUsageMap[groupByString] = data
			} else {
				limitedUsageMap = addUsageToAllOtherUsageInMap(data, limitedUsageMap)
			}
		}

		// now that we have usage for our top resource IDs and all usage in the usage map, we want to decrement
		// the "all usage" total by the amount in each top resource ID to build the "all other" usage
		for _, topResourceId := range topResourceIDs {
			topResourceIdString := strconv.FormatInt(topResourceId, 10)

			limitedUsageMap[allOther].totalAmount -= limitedUsageMap[topResourceIdString].totalAmount
			for usageItemUsageAtKey, usageItem := range limitedUsageMap[topResourceIdString].data {
				for allOtherUsageItemUsageAtKey, allOtherUsageItem := range limitedUsageMap[allOther].data {
					// these usage at date keys are truncated so we can compare them directly
					if allOtherUsageItemUsageAtKey == usageItemUsageAtKey {
						allOtherUsageItem.billedAmount -= usageItem.billedAmount
						allOtherUsageItem.discountAmount -= usageItem.discountAmount
						allOtherUsageItem.totalAmount -= usageItem.totalAmount
					}
				}
			}
		}
	} else {
		for groupByString, data := range usageMap {
			if len(limitedUsageMap) < topN {
				limitedUsageMap[groupByString] = data
			} else {
				// Find the smallest value in values
				minValue := data.totalAmount
				minValueKey := groupByString
				for limitedUsageMapGroupByString := range limitedUsageMap {
					if limitedUsageMapGroupByString != allOther && limitedUsageMap[limitedUsageMapGroupByString].totalAmount < minValue {
						minValue = limitedUsageMap[limitedUsageMapGroupByString].totalAmount
						minValueKey = limitedUsageMapGroupByString
					}
				}
				if minValueKey == groupByString {
					// This is the minimum value, add it to all other usage
					limitedUsageMap = addUsageToAllOtherUsageInMap(data, limitedUsageMap)
				} else {
					// This is not the minimum value, add this usage, remove smallest usage and add smallest usage to all other usage
					limitedUsageMap[groupByString] = data
					addUsageToAllOtherUsageInMap(limitedUsageMap[minValueKey], limitedUsageMap)
					delete(limitedUsageMap, minValueKey)
				}
			}
		}
	}

	return limitedUsageMap
}

func addUsageToAllOtherUsageInMap(usage *UsageMap, usageMap map[string]*UsageMap) map[string]*UsageMap {
	if _, ok := usageMap[allOther]; !ok {
		usageMap[allOther] = &UsageMap{
			name:        allOther,
			data:        map[string]*UsageChartItem{},
			totalAmount: 0,
		}
	}

	usageMap[allOther].totalAmount += usage.totalAmount
	usageMap[allOther].data = mergeUsageItems(usageMap[allOther].data, usage.data)

	return usageMap
}

func mergeUsageItems(usageItems1 map[string]*UsageChartItem, usageItems2 map[string]*UsageChartItem) map[string]*UsageChartItem {
	mergedUsageItems := make(map[string]*UsageChartItem)

	// Merge any overlapping items between usageItems2 and usageItems1
	for key, value := range usageItems2 {
		if _, ok := usageItems1[key]; ok {
			mergedUsageItems[key] = &UsageChartItem{
				billedAmount:   usageItems1[key].billedAmount + value.billedAmount,
				discountAmount: usageItems1[key].discountAmount + value.discountAmount,
				usageAt:        value.usageAt,
				totalAmount:    usageItems1[key].totalAmount + value.totalAmount,
			}
		} else {
			mergedUsageItems[key] = &UsageChartItem{
				billedAmount:   value.billedAmount,
				discountAmount: value.discountAmount,
				usageAt:        value.usageAt,
				totalAmount:    value.totalAmount,
			}
		}
	}

	// Add any values that aren't in usageItems2
	for key, value := range usageItems1 {
		if _, ok := mergedUsageItems[key]; !ok {
			mergedUsageItems[key] = &UsageChartItem{
				billedAmount:   value.billedAmount,
				discountAmount: value.discountAmount,
				usageAt:        value.usageAt,
				totalAmount:    value.totalAmount,
			}
		}
	}

	return mergedUsageItems
}

func transformUsageMapToUsageChartDatasets(usageMap map[string]*UsageMap, input *proto.GetUsageChartDataRequest) []*proto.UsageChartDataset {
	// This logic will set up the blank data for each dataset, which represents one line each in the usage chart
	// If we ever create different time groupings for the usage chart, they should be added in this method
	datasets := getBlankDatasetsFromInput(input, len(usageMap))

	return fillInDatasetsWithUsageMap(datasets, usageMap, input.BillingPeriod)
}

func getBlankDatasetsFromInput(input *proto.GetUsageChartDataRequest, size int) []*proto.UsageChartDataset {
	// Find request type
	now := time.Now().UTC()
	billingPeriodRequestType := findBillingPeriodRequestType(int(input.GetYear()), int(input.GetMonth()), int(input.GetDay()), input.GetBillingPeriod(), now)

	return generateBlankDatasets(now, size, billingPeriodRequestType)
}

func findBillingPeriodRequestType(requestYear int, requestMonth int, requestDay int, billingPeriod proto.BillingPeriod, now time.Time) string {
	requestDate := time.Date(requestYear, time.Month(requestMonth), int(requestDay), 0, 0, 0, 0, time.UTC)

	switch billingPeriod {
	case proto.BillingPeriod_Hourly:
		return BillingPeriodRequestTypeThisHour
	case proto.BillingPeriod_Daily:
		return BillingPeriodRequestTypeToday
	case proto.BillingPeriod_Monthly:
		if requestDate.Year() == now.Year() && requestDate.Month() == now.Month() {
			return BillingPeriodRequestTypeThisMonth
		}
		return BillingPeriodRequestTypeLastMonth
	case proto.BillingPeriod_Yearly:
		if requestDate.Year() == now.Year() {
			return BillingPeriodRequestTypeThisYear
		} else if requestDate.Year() == now.Year()-1 {
			return BillingPeriodRequestTypeLastYear
		}
	}
	return BillingPeriodRequestTypeThisMonth
}

func generateBlankDatasets(now time.Time, size int, billingPeriodRequestType string) []*proto.UsageChartDataset {
	datasets := make([]*proto.UsageChartDataset, size)
	dataSize := getDataSize(now, billingPeriodRequestType)
	dataStartFrom := getDataStartFrom(billingPeriodRequestType)

	for i := 0; i < size; i++ {
		data := make([]*proto.UsageChartData, dataSize)
		for j := dataStartFrom; j < dataSize+dataStartFrom; j++ {
			data[j-dataStartFrom] = &proto.UsageChartData{
				Y: 0,
				X: getTimeForDataEntry(now, billingPeriodRequestType, j),
				Custom: &proto.CustomFields{
					DiscountAmount: "",
					GrossAmount:    "",
					TotalAmount:    "",
				},
			}
		}
		datasets[i] = &proto.UsageChartDataset{
			Name: "",
			Data: data,
		}
	}

	return datasets
}

func getDataSize(now time.Time, billingPeriodRequestType string) int {
	switch billingPeriodRequestType {
	case BillingPeriodRequestTypeThisHour:
		return now.Minute()
	case BillingPeriodRequestTypeToday:
		return now.Hour()
	case BillingPeriodRequestTypeThisMonth:
		return now.Day()
	case BillingPeriodRequestTypeLastMonth:
		return time.Date(now.Year(), now.Month(), 0, 0, 0, 0, 0, time.UTC).Day()
	case BillingPeriodRequestTypeThisYear:
		return int(now.Month())
	case BillingPeriodRequestTypeLastYear:
		return 12
	default:
		return now.Day()
	}
}

func getDataStartFrom(billingPeriodRequestType string) int {
	switch billingPeriodRequestType {
	case BillingPeriodRequestTypeThisHour:
		return 0
	case BillingPeriodRequestTypeToday:
		return 0
	case BillingPeriodRequestTypeThisMonth:
		return 1
	case BillingPeriodRequestTypeLastMonth:
		return 1
	case BillingPeriodRequestTypeThisYear:
		return 1
	case BillingPeriodRequestTypeLastYear:
		return 1
	default:
		return 1
	}
}

func getTimeForDataEntry(now time.Time, billingPeriodRequestType string, j int) int64 {
	switch billingPeriodRequestType {
	case BillingPeriodRequestTypeThisHour:
		return time.Date(now.Year(), now.Month(), now.Day(), now.Hour(), j, 0, 0, time.UTC).UnixMilli()
	case BillingPeriodRequestTypeToday:
		return time.Date(now.Year(), now.Month(), now.Day(), j, 0, 0, 0, time.UTC).UnixMilli()
	case BillingPeriodRequestTypeThisMonth:
		return time.Date(now.Year(), now.Month(), j, 0, 0, 0, 0, time.UTC).UnixMilli()
	case BillingPeriodRequestTypeLastMonth:
		month := time.Date(now.Year(), now.Month(), 0, 0, 0, 0, 0, time.UTC).Month()
		year := time.Date(now.Year(), now.Month(), 0, 0, 0, 0, 0, time.UTC).Year()
		return time.Date(year, month, j, 0, 0, 0, 0, time.UTC).UnixMilli()
	case BillingPeriodRequestTypeThisYear:
		return time.Date(now.Year(), time.Month(j), 1, 0, 0, 0, 0, time.UTC).UnixMilli()
	case BillingPeriodRequestTypeLastYear:
		return time.Date(now.Year()-1, time.Month(j), 1, 0, 0, 0, 0, time.UTC).UnixMilli()
	default:
		return time.Date(now.Year(), now.Month(), j, 0, 0, 0, 0, time.UTC).UnixMilli()
	}
}

func fillInDatasetsWithUsageMap(datasets []*proto.UsageChartDataset, usageMap map[string]*UsageMap, period proto.BillingPeriod) []*proto.UsageChartDataset {
	// Iterate through each usageMap and fill in data
	i := 0
	for _, usageMapValue := range usageMap {
		datasets[i].Name = usageMapValue.name
		sum := float64(0)
		for _, data := range datasets[i].Data {
			timestamp := getUsageTimestamp(data.X, period)
			usageItem := usageMapValue.data[timestamp]
			if usageItem != nil {
				sum += usageItem.billedAmount

				discountAmount := fmt.Sprintf("$%.2f", usageItem.discountAmount)
				totalAmount := fmt.Sprintf("$%.2f", usageItem.totalAmount)

				data.Custom = &proto.CustomFields{
					DiscountAmount: discountAmount,
					GrossAmount:    fmt.Sprintf("$%.2f", usageItem.billedAmount),
					TotalAmount:    totalAmount,
				}
			} else {
				data.Custom = &proto.CustomFields{
					DiscountAmount: "N/A",
					GrossAmount:    "N/A",
					TotalAmount:    "N/A",
				}
			}

			data.Y = math.Round(sum*100) / 100
		}
		i++
	}

	sortByTotalAmount(datasets)

	return datasets
}

func sortByTotalAmount(datasets []*proto.UsageChartDataset) []*proto.UsageChartDataset {
	// Sort datasets by largest totalAmount in the last entry
	sortBy := func(c1, c2 *proto.UsageChartDataset) bool {
		if len(c1.Data) == 0 || len(c2.Data) == 0 {
			return false
		}
		return c1.Data[len(c1.Data)-1].Y > c2.Data[len(c2.Data)-1].Y
	}
	sort.Slice(datasets, func(i, j int) bool {
		return sortBy(datasets[i], datasets[j])
	})

	// Move "All other" to the end, if present
	for i, dataset := range datasets {
		if dataset.Name == allOther {
			datasets = append(datasets[:i], datasets[i+1:]...)
			datasets = append(datasets, dataset)
			break
		}
	}

	return datasets
}
