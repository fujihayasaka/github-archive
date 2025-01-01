package models

import (
	"fmt"
	"strconv"
	"strings"
)

const (
	ByProductSkuGrouping        = "byProductSku"
	ByOrgAndRepoGrouping        = "byOrgAndRepo"
	ByOrgRepoProductSkuGrouping = "byOrgRepoProductSku"
	ByCostCenter                = "byCostCenter"
)

type UsagePartitionDetail struct {
	UsageEntityId string
	Product       string
	Sku           string
	RepoId        int64
	OrgId         int64
	UsageTime     *UsageTime
	ActiveType    ActiveType
	GroupBy       string

	IsOrgAdmin bool
}

func (upd *UsagePartitionDetail) ToPartitionKey() string {
	parts := []string{
		upd.UsageEntityId,
		upd.Product,
		upd.Sku,
		upd.UsageTime.ToPartitionKey(upd.ActiveType),
	}

	compactParts := []string{}

	for _, part := range parts {
		if part != "" {
			compactParts = append(compactParts, part)
		}
	}

	return strings.Join(compactParts, ":")
}

func (upd *UsagePartitionDetail) ToEventPartitionKey() string {
	return fmt.Sprintf("%s:%s:events", upd.UsageEntityId, upd.Sku)
}

func (upd *UsagePartitionDetail) ToEventPartitionKeyWithYearMonth() string {
	return fmt.Sprintf("%s:%s:events:%d:%d", upd.UsageEntityId, upd.Sku, upd.UsageTime.Year(), upd.UsageTime.Month())
}

func (upd *UsagePartitionDetail) ToDiscountsPartitionKey() string {
	// Discount partitions do not include the Product
	parts := []string{
		upd.UsageEntityId,
		upd.Sku,
		upd.UsageTime.ToPartitionKey(upd.ActiveType),
		"discount",
	}

	if upd.OrgId != 0 {
		parts = []string{
			upd.UsageEntityId,
			"org",
			strconv.FormatInt(upd.OrgId, 10),
			upd.UsageTime.ToPartitionKey(upd.ActiveType),
			"byProductSku",
			"discount",
		}
	}

	if upd.RepoId != 0 {
		parts = []string{
			upd.UsageEntityId,
			"repo",
			strconv.FormatInt(upd.RepoId, 10),
			upd.UsageTime.ToPartitionKey(upd.ActiveType),
			"byProductSku",
			"discount",
		}
	}

	compactParts := []string{}

	for _, part := range parts {
		if part != "" {
			compactParts = append(compactParts, part)
		}
	}

	return strings.Join(compactParts, ":")
}

func (upd *UsagePartitionDetail) HasSearchFilters() bool {
	return upd.Product != "" || upd.Sku != "" || upd.RepoId != 0 || upd.OrgId != 0
}

func (upd *UsagePartitionDetail) ToGetLineItemsPartitionKey() string {
	parts := []string{
		upd.UsageEntityId,
		upd.Product,
		upd.Sku,
		upd.UsageTime.ToPartitionKey(upd.ActiveType),
	}

	// In the event that both org and repo are set, repo takes precedence
	// They shouldn't be both present to begin with. One possible solution is validations in Dotcom (or elsewhere)
	// For now this is fine, will try to strategize a bit better during my work for org/repo/product/sku group by work
	if upd.OrgId != 0 {
		parts = []string{
			upd.UsageEntityId,
			"org",
			strconv.FormatInt(upd.OrgId, 10),
			upd.UsageTime.ToPartitionKey(upd.ActiveType),
		}
	}

	if upd.RepoId != 0 {
		parts = []string{
			upd.UsageEntityId,
			"repo",
			strconv.FormatInt(upd.RepoId, 10),
			upd.UsageTime.ToPartitionKey(upd.ActiveType),
		}
	}

	// Determine if we should add a group by suffix (e.g. byProductSku, byOrgAndRepo, byOrgRepoProductSku)
	switch {
	// Add byProductSku to org and repo queries with no groupings
	case upd.GroupBy == "" && (upd.OrgId != 0 || upd.RepoId != 0):
		parts = append(parts, ByProductSkuGrouping)
	// Add byProductSku to org and repo queries that are grouped by product or sku
	case upd.GroupBy == ByProductSkuGrouping && (upd.OrgId != 0 || upd.RepoId != 0):
		parts = append(parts, ByProductSkuGrouping)
	// Add byProductSku to org and repo queries that are grouped by cost center
	case upd.GroupBy == ByCostCenter && (upd.OrgId != 0 || upd.RepoId != 0):
		parts = append(parts, ByProductSkuGrouping)
	// Add byProductSku to org and repo queries that are grouped by org and repo
	case upd.GroupBy == ByOrgAndRepoGrouping && (upd.OrgId != 0 || upd.RepoId != 0):
		parts = append(parts, ByProductSkuGrouping)
	// Add byOrgAndRepo to org/repo grouping usage queries without search filters
	case upd.GroupBy == ByOrgAndRepoGrouping && !upd.HasSearchFilters():
		parts = append(parts, upd.GroupBy)
	// Add byOrgRepoProductSku to OrgRepoProductSku grouping usage queries without search filters
	case upd.GroupBy == ByOrgRepoProductSkuGrouping && !upd.HasSearchFilters():
		parts = append(parts, upd.GroupBy)
	}

	compactParts := []string{}

	for _, part := range parts {
		if part != "" {
			compactParts = append(compactParts, part)
		}
	}

	return strings.Join(compactParts, ":")
}

func (upd *UsagePartitionDetail) ToRepoPartitionKey() string {
	compactParts := []string{}
	parts := []string{
		upd.UsageEntityId,
		"repo",
		strconv.Itoa(int(upd.RepoId)),
		upd.UsageTime.ToPartitionKey(upd.ActiveType),
	}

	for _, part := range parts {
		if part != "" {
			compactParts = append(compactParts, part)
		}
	}

	return strings.Join(compactParts, ":")
}

func (upd *UsagePartitionDetail) ToRepoProductSkuPartitionKey() string {
	compactParts := []string{}
	parts := []string{
		upd.UsageEntityId,
		"repo",
		strconv.Itoa(int(upd.RepoId)),
		"sku",
		upd.Sku,
		upd.UsageTime.ToPartitionKey(upd.ActiveType),
	}

	for _, part := range parts {
		if part != "" {
			compactParts = append(compactParts, part)
		}
	}

	return strings.Join(compactParts, ":")
}

func GetPartitionDetailForItemDiscountLookup(item *Item) (*UsagePartitionDetail, error) {
	activeType := Daily

	return &UsagePartitionDetail{
		UsageEntityId: item.GetCustomerId(),
		UsageTime:     &item.UsageAt,
		ActiveType:    activeType,
		Sku:           item.GetSku(),
	}, nil
}

func (upd *UsagePartitionDetail) ToLateDiscountPartitionKey() string {
	return fmt.Sprintf("%s:%d:%d:%d:lateDiscounts", upd.UsageEntityId, upd.UsageTime.Year(), upd.UsageTime.Month(), upd.UsageTime.Day())
}

func (upd *UsagePartitionDetail) ToDailyZuoraEmissionPartitionKey() string {
	return fmt.Sprintf("%s:%d:%d:%d:byZuoraEmission", upd.Sku, upd.UsageTime.Year(), upd.UsageTime.Month(), upd.UsageTime.Day())
}

type PartitionDetailUsageItemResults struct {
	UsagePartitionDetail *UsagePartitionDetail
	UsageItems           []*UsageItem
}
