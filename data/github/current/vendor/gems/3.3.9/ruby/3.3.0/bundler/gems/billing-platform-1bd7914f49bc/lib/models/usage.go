package models

import "github.com/github/billing-platform/lib/twirp/proto"

type UsageRequest struct {
	CustomerId    int64
	CostCenterId  string
	Limit         int32
	Year          int64
	Month         int64
	Day           int64
	Hour          int64
	BillingPeriod proto.BillingPeriod
	GroupBy       proto.UsageGroupBy
	Product       string
	Sku           string
	RepoId        int64
	OrgId         int64
	FilteredOrgs  []int64
}
