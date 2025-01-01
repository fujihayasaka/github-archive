package models

// ZuoraEmissionRollup represents the Zuora emission rollup model
type ZuoraEmissionRollup struct {
	CustomerID   string
	ProductSKU   string
	Year         int
	Month        int
	Day          int
	PartitionKey string
	ID           string
}

func GetPartitionDetailForDailyZuoraEmission(usageDate *EmissionTarget) (*UsagePartitionDetail, error) {
	activeType := Daily
	usageTime := NewUsageTime().WithYear(usageDate.Year).WithMonthInt(usageDate.Month).WithDay(int(usageDate.Day))

	return &UsagePartitionDetail{
		UsageTime:  usageTime,
		ActiveType: activeType,
	}, nil
}
