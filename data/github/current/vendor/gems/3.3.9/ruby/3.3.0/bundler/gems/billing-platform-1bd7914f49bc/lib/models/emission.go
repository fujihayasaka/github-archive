package models

import (
	"fmt"
	"strconv"
	"strings"
	"time"
)

type EmissionTarget struct {
	Year  int64
	Month int64
	Day   int64
}

type EmissionStatus byte

const (
	EmissionNew EmissionStatus = iota
	EmissionCompleted
	EmissionFailed
	EmissionIgnored
)

type EmissionPartitionDetail struct {
	CustomerId string
	Year       int64
	Month      int64
	Day        int64
}

type Emission struct {
	*Key
	UsagePartitionKey string
	CostCenter        string
	UsageTotal        *UsageTotal
	ProductTotals     map[string]*ProductTotal
	Status            EmissionStatus
	ErrorMessage      string
}

func NewEmissionKey(epd *EmissionPartitionDetail) *Key {
	partitionKey := GetEmissionsPartitionKey(epd)
	return &Key{
		PartitionKey: fmt.Sprintf("%s:%d:%d", partitionKey, epd.Year, epd.Month),
		Id:           fmt.Sprintf("%s:%d:%d:%d", partitionKey, epd.Year, epd.Month, epd.Day),
	}
}

func NewEmission(epd *EmissionPartitionDetail, items []*Item, discountItems []*DiscountItem, costcenter *CostCenter) *Emission {
	var costCenterUUID string
	if condition := costcenter != nil; condition {
		costCenterUUID = costcenter.UUID

	}

	Emission := &Emission{
		Key:           NewEmissionKey(epd),
		CostCenter:    costCenterUUID,
		Status:        EmissionNew,
		UsageTotal:    &UsageTotal{},
		ProductTotals: map[string]*ProductTotal{},
	}
	totals := &Totals{
		UsageTotal:    &UsageTotalNano{},
		ProductTotals: map[string]*ProductTotalNano{},
	}

	for _, item := range items {
		product := item.GetProduct()
		sku := item.GetSku()
		productTotal, ok := totals.ProductTotals[product]
		if !ok {
			productTotal = &ProductTotalNano{
				Product:    product,
				UsageTotal: &UsageTotalNano{},
				SkuTotals:  map[string]*SkuTotalNano{},
			}
			totals.ProductTotals[product] = productTotal
		}

		skuTotal, ok := productTotal.SkuTotals[sku]
		if !ok {
			skuTotal = &SkuTotalNano{
				Sku:        sku,
				UsageTotal: &UsageTotalNano{},
			}
			productTotal.SkuTotals[sku] = skuTotal
		}
		if item.Amounts != nil {
			SaveBillingAmounts(skuTotal.UsageTotal, item)
			SaveBillingAmounts(productTotal.UsageTotal, item)
			SaveBillingAmounts(totals.UsageTotal, item)
		}
		skuTotal.BillingItems = append(skuTotal.BillingItems, item)
	}

	for _, item := range discountItems {
		ApplyDiscount(totals.UsageTotal, item)
		productTotal := totals.ProductTotals[item.asBillingItem().GetProduct()]
		ApplyDiscount(productTotal.UsageTotal, item)
		ApplyDiscount(productTotal.SkuTotals[item.asBillingItem().GetSku()].UsageTotal, item)
	}

	return AddTotalsToEmission(Emission, totals)
}

func AddTotalsToEmission(emission *Emission, totals *Totals) *Emission {
	emission.UsageTotal = ConvertTotalsToFloats(emission.UsageTotal, totals.UsageTotal)
	for product, productTotals := range totals.ProductTotals {
		skuTotalsNano := map[string]*SkuTotal{}
		for sku, skuTotals := range productTotals.SkuTotals {
			skuTotalsNano[sku] = &SkuTotal{
				Sku:          sku,
				UsageTotal:   ConvertTotalsToFloats(&UsageTotal{}, skuTotals.UsageTotal),
				BillingItems: skuTotals.BillingItems,
			}
		}

		emission.ProductTotals[product] = &ProductTotal{
			Product:    product,
			UsageTotal: ConvertTotalsToFloats(&UsageTotal{}, productTotals.UsageTotal),
			SkuTotals:  skuTotalsNano,
		}

	}

	return emission
}

func GetEmissionsPartitionKey(epd *EmissionPartitionDetail) string {
	return fmt.Sprintf("%s:Emission", epd.CustomerId)
}

func (s EmissionStatus) GetStatusString() string {
	switch s {
	case EmissionNew:
		return "New"
	case EmissionCompleted:
		return "Completed"
	case EmissionFailed:
		return "Failed"
	case EmissionIgnored:
		return "Ignored"
	default:
		return "Unknown"
	}
}

func GetUsageTimeFromEmissionTarget(emissionTarget *EmissionTarget) UsageTime {
	day, _ := convertDayToInt(emissionTarget.Day)
	usageTime := NewUsageTime().WithYear(emissionTarget.Year).WithMonthInt(emissionTarget.Month).WithDay(day)
	return *usageTime
}

// Extracts the year, month, and day from a partition key of the format "activeUsageItems:YYYY:M:D"
func ExtractEmissionDateFromPartitionKey(partitionKey string) (*EmissionTarget, error) {
	var year, month, day int64
	parts := strings.Split(partitionKey, ":")
	if len(parts) != 4 {
		return nil, fmt.Errorf("invalid partition key format")
	}

	year, err := strconv.ParseInt(parts[1], 10, 64)
	if err != nil {
		return nil, fmt.Errorf("invalid year format")
	}

	month, err = strconv.ParseInt(parts[2], 10, 64)
	if err != nil {
		return nil, fmt.Errorf("invalid month format")
	}

	day, err = strconv.ParseInt(parts[3], 10, 64)
	if err != nil {
		return nil, fmt.Errorf("invalid day format")
	}

	return &EmissionTarget{
		Year:  year,
		Month: month,
		Day:   day,
	}, nil
}

func GetPartitionDetailForDailyRollups(emissionTarget *EmissionTarget, customerid string) (*UsagePartitionDetail, error) {
	activeType := Daily
	day, err := convertDayToInt(emissionTarget.Day)
	if err != nil {
		return nil, fmt.Errorf("day value exceeds the maximum size for int")
	}

	usageTime := NewUsageTime().WithYear(emissionTarget.Year).WithMonthInt(emissionTarget.Month).WithDay(day)

	return &UsagePartitionDetail{
		UsageEntityId: customerid,
		UsageTime:     usageTime,
		Product:       "",
		Sku:           "",
		ActiveType:    activeType,
	}, nil
}

// convertDayToInt converts a 64-bit integer day to an int with bounds checking.
// Returns an error if the day exceeds the maximum size for int.
func convertDayToInt(day int64) (int, error) {
	if day > int64(^uint32(0)>>1) { // Check against max int32 value
		return 0, fmt.Errorf("day value exceeds the maximum size for int")
	}
	return int(day), nil
}

func GetNewPartitionEmissionDetailsForStart(customer *Customer) (*EmissionPartitionDetail, error) {
	currentDate := time.Now()
	return &EmissionPartitionDetail{
		CustomerId: customer.GetCustomerId(),
		Year:       int64(currentDate.Year()),
		Month:      int64(currentDate.Month()),
		Day:        int64(currentDate.Day()),
	}, nil
}

func GetDateFromEmissionPartitionDetail(emissionKey *Key) UsageTime {
	parts := strings.Split(emissionKey.Id, ":")
	Year, err := strconv.ParseInt(parts[2], 10, 64)
	if err != nil {
		fmt.Println("Error parsing year:", err)
	}

	Month, err := strconv.ParseInt(parts[3], 10, 64)
	if err != nil {
		fmt.Println("Error parsing month:", err)
	}

	day, err := strconv.Atoi(parts[4])
	if err != nil {
		fmt.Println("Error parsing day:", err)
	}
	usageTime := NewUsageTime().WithYear(Year).WithMonthInt(Month).WithDay(day)

	return *usageTime
}
