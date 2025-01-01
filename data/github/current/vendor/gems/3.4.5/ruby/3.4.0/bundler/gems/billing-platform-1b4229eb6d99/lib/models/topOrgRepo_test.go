package models

import (
	"testing"

	"github.com/github/billing-platform/lib/twirp/proto"
	"github.com/stretchr/testify/assert"
)

func Test_NewCacheKeyForTopOrgRepoInput(t *testing.T) {
	tests := []struct {
		name     string
		input    *UsageRequest
		expected *Key
	}{
		{
			name: "Group by org",
			input: &UsageRequest{
				CustomerId:    1,
				Year:          2021,
				BillingPeriod: proto.BillingPeriod_Yearly,
				GroupBy:       proto.UsageGroupBy_GroupByOrganization,
			},
			expected: &Key{
				PartitionKey: "1:2021:topOrgs",
				Id:           topOrgsID,
			},
		},
		{
			name: "Group by repo",
			input: &UsageRequest{
				CustomerId:    1,
				Year:          2021,
				BillingPeriod: proto.BillingPeriod_Yearly,
				GroupBy:       proto.UsageGroupBy_GroupByRepository,
			},
			expected: &Key{
				PartitionKey: "1:2021:topRepos",
				Id:           topReposID,
			},
		},
		{
			name: "Cost center ID",
			input: &UsageRequest{
				CustomerId:    1,
				CostCenterId:  "cost-center",
				Year:          2021,
				Month:         1,
				Day:           2,
				Hour:          3,
				BillingPeriod: proto.BillingPeriod_Hourly,
				GroupBy:       proto.UsageGroupBy_GroupByOrganization,
			},
			expected: &Key{
				PartitionKey: "cost-center:2021:1:2:3:topOrgs",
				Id:           topOrgsID,
			},
		},
		{
			name: "Yearly period",
			input: &UsageRequest{
				CustomerId:    1,
				Year:          2021,
				Month:         1,
				Day:           2,
				Hour:          3,
				BillingPeriod: proto.BillingPeriod_Yearly,
				GroupBy:       proto.UsageGroupBy_GroupByOrganization,
			},
			expected: &Key{
				PartitionKey: "1:2021:topOrgs",
				Id:           topOrgsID,
			},
		},
		{
			name: "Monthly period",
			input: &UsageRequest{
				CustomerId:    1,
				Year:          2021,
				Month:         1,
				Day:           2,
				Hour:          3,
				BillingPeriod: proto.BillingPeriod_Monthly,
				GroupBy:       proto.UsageGroupBy_GroupByOrganization,
			},
			expected: &Key{
				PartitionKey: "1:2021:1:topOrgs",
				Id:           topOrgsID,
			},
		},
		{
			name: "Daily period",
			input: &UsageRequest{
				CustomerId:    1,
				Year:          2021,
				Month:         1,
				Day:           2,
				Hour:          3,
				BillingPeriod: proto.BillingPeriod_Daily,
				GroupBy:       proto.UsageGroupBy_GroupByOrganization,
			},
			expected: &Key{
				PartitionKey: "1:2021:1:2:topOrgs",
				Id:           topOrgsID,
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			assert.Equal(t, tt.expected, NewTopOrgRepoCacheKey(tt.input))
		})
	}
}
