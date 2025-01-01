package models

import (
	"fmt"

	"github.com/github/billing-platform/lib/twirp/proto"
)

const (
	topOrgsID  = "topOrgs"
	topReposID = "topRepos"
)

type TopOrgRepo struct {
	*Key
	ResourceIDs []int64 `json:"resourceIds"`
	Timestamp   int64   `json:"_ts"`
}

func NewTopOrgRepoCacheKey(input *UsageRequest) *Key {
	usageTime := NewUsageTime().WithYear(input.Year).WithMonthInt(input.Month).WithDay(int(input.Day)).WithHour(int(input.Hour))
	usageTimePartitionKey := usageTime.ToPartitionKey(toActiveType(input.BillingPeriod))

	var id string
	if input.GroupBy == proto.UsageGroupBy_GroupByRepository {
		id = topReposID
	} else {
		id = topOrgsID
	}

	customerOrCostCenterId := fmt.Sprintf("%d", input.CustomerId)
	if input.CostCenterId != "" && input.CostCenterId != "All" {
		customerOrCostCenterId = input.CostCenterId
	}

	return &Key{
		PartitionKey: fmt.Sprintf("%s:%s:%s", customerOrCostCenterId, usageTimePartitionKey, id),
		Id:           id,
	}
}

func toActiveType(billingPeriod proto.BillingPeriod) ActiveType {
	var period ActiveType
	switch billingPeriod {
	case proto.BillingPeriod_Hourly:
		period = Hourly
	case proto.BillingPeriod_Daily:
		period = Daily
	case proto.BillingPeriod_Monthly:
		period = Monthly
	case proto.BillingPeriod_Yearly:
		period = Yearly
	default:
		return Unknown
	}
	return period
}
