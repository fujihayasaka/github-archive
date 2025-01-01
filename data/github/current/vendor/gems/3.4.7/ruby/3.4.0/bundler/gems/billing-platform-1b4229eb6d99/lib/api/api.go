package api

import (
	"fmt"
	"slices"
	"strconv"

	"github.com/github/billing-platform/lib/models"
	"github.com/github/billing-platform/lib/twirp/proto"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/pkg/errors"
)

const topN = 5

func FromInvoiceRequestToUsagePartitionDetail(invoiceRequest *proto.GetInvoiceRequest) *models.UsagePartitionDetail {
	usageTime := models.NewUsageTime().WithYear(invoiceRequest.Year).WithMonthInt(invoiceRequest.Month)

	return &models.UsagePartitionDetail{
		UsageEntityId: invoiceRequest.CustomerId,
		Product:       "",
		Sku:           "",
		UsageTime:     usageTime,
		ActiveType:    models.Monthly,
	}
}

func FromTopOrgRepoUsageRequestToUsagePartitionDetail(resourceID int64, topUsageRequest *proto.TopOrgRepoUsageRequest, entityId string) (*models.UsagePartitionDetail, error) {
	activeType, err := toActiveType(topUsageRequest.BillingPeriod)
	if err != nil {
		return nil, err
	}

	usageTime := models.NewUsageTime().WithYear(topUsageRequest.Year).WithMonthInt(topUsageRequest.Month).WithDay(int(topUsageRequest.Day)).WithHour(int(topUsageRequest.Hour))
	upd := &models.UsagePartitionDetail{
		UsageEntityId: entityId,
		UsageTime:     usageTime,
		ActiveType:    activeType,
	}
	if topUsageRequest.GroupBy == proto.UsageGroupBy_GroupByRepository {
		upd.RepoId = resourceID
	} else {
		upd.OrgId = resourceID
	}

	return upd, nil
}

func FromTopOrgRepoUsageRequestToUsagePartitionDetailForOthers(topUsageRequest *proto.TopOrgRepoUsageRequest, entityId string) (*models.UsagePartitionDetail, error) {
	activeType, err := toActiveType(topUsageRequest.BillingPeriod)
	if err != nil {
		return nil, err
	}

	usageTime := models.NewUsageTime().WithYear(topUsageRequest.Year).WithMonthInt(topUsageRequest.Month).WithDay(int(topUsageRequest.Day)).WithHour(int(topUsageRequest.Hour))
	upd := &models.UsagePartitionDetail{
		UsageEntityId: entityId,
		UsageTime:     usageTime,
		ActiveType:    activeType,
	}

	return upd, nil
}

func FromOrgAdminTopOrgRepoUsageRequestToUsagePartitionDetailForOthers(topUsageRequest *proto.TopOrgRepoUsageRequest, entityId string, orgId int64) (*models.UsagePartitionDetail, error) {
	activeType, err := toActiveType(topUsageRequest.BillingPeriod)
	if err != nil {
		return nil, err
	}

	usageTime := models.NewUsageTime().WithYear(topUsageRequest.Year).WithMonthInt(topUsageRequest.Month).WithDay(int(topUsageRequest.Day)).WithHour(int(topUsageRequest.Hour))
	upd := &models.UsagePartitionDetail{
		UsageEntityId: entityId,
		UsageTime:     usageTime,
		ActiveType:    activeType,
		OrgId:         orgId,
	}

	return upd, nil
}

func FromUsageRequestToUsagePartitionDetail(usageRequest *proto.GetUsageRequest) (*models.UsagePartitionDetail, error) {
	activeType, err := toActiveType(usageRequest.BillingPeriod)
	if err != nil {
		return nil, err
	}
	groupBySuffix, err := toGroupBySuffix(usageRequest.GroupBy)
	if err != nil {
		return nil, err
	}

	usageTime := models.NewUsageTime().WithYear(usageRequest.Year).WithMonthInt(usageRequest.Month).WithDay(int(usageRequest.Day)).WithHour(int(usageRequest.Hour))

	return &models.UsagePartitionDetail{
		UsageEntityId: usageRequest.UsageEntityId,
		Product:       usageRequest.Product,
		Sku:           usageRequest.Sku,
		UsageTime:     usageTime,
		ActiveType:    activeType,
		RepoId:        usageRequest.RepoId,
		OrgId:         usageRequest.OrgId,
		GroupBy:       groupBySuffix,
	}, nil
}

func FromEnterpriseUsageTotalsRequestToUsagePartitionDetails(usageRequest *proto.GetEnterpriseUsageTotalsRequest, costCenters []*models.CostCenter) ([]*models.UsagePartitionDetail, error) {
	partitionDetails := make([]*models.UsagePartitionDetail, 0)
	isOrgAdminRequest := len(usageRequest.OrganizationAdminIds) > 0

	// usage totals show usage for the current month, so we only need to query the yearly usage partition, and then we can filter
	// for the monthly usage document ID
	usageTime := models.NewUsageTime().WithYear(usageRequest.Year)

	for _, costCenter := range costCenters {
		if isOrgAdminRequest {
			for _, orgAdminId := range usageRequest.OrganizationAdminIds {
				partitionDetails = append(partitionDetails, &models.UsagePartitionDetail{
					UsageEntityId: costCenter.Id,
					UsageTime:     usageTime,
					ActiveType:    models.Yearly,
					OrgId:         orgAdminId,
				})
			}
		} else {
			partitionDetails = append(partitionDetails, &models.UsagePartitionDetail{
				UsageEntityId: costCenter.Id,
				UsageTime:     usageTime,
				ActiveType:    models.Yearly,
			})
		}
	}

	if isOrgAdminRequest {
		for _, orgAdminId := range usageRequest.OrganizationAdminIds {
			partitionDetails = append(partitionDetails, &models.UsagePartitionDetail{
				UsageEntityId: usageRequest.CustomerId,
				UsageTime:     usageTime,
				ActiveType:    models.Yearly,
				OrgId:         orgAdminId,
			})
		}
	} else {
		partitionDetails = append(partitionDetails, &models.UsagePartitionDetail{
			UsageEntityId: usageRequest.CustomerId,
			UsageTime:     usageTime,
			ActiveType:    models.Yearly,
		})
	}

	return partitionDetails, nil
}

func FromUsageRequestToUsagePartitionDetails(usageRequest *proto.GetUsageRequest, costCenters []*models.CostCenter) ([]*models.UsagePartitionDetail, error) {
	activeType, err := toActiveType(usageRequest.BillingPeriod)
	if err != nil {
		return nil, err
	}
	groupBySuffix, err := toGroupBySuffix(usageRequest.GroupBy)
	if err != nil {
		return nil, err
	}

	usageTime := models.NewUsageTime().WithYear(usageRequest.Year).WithMonthInt(usageRequest.Month).WithDay(int(usageRequest.Day)).WithHour(int(usageRequest.Hour))

	partitionDetails := make([]*models.UsagePartitionDetail, 0)
	switch usageRequest.CostCenterId {
	case "none":
		// This is a search for data not associated with a cost center, return just this partition detail
		partitionDetails = createPartitionDetailsForUsageRequest(usageRequest, partitionDetails, usageTime, activeType, groupBySuffix, usageRequest.UsageEntityId)
	case "All", "":
		// All usage incurred in all cost centers
		for _, costCenter := range costCenters {
			partitionDetails = createPartitionDetailsForUsageRequest(usageRequest, partitionDetails, usageTime, activeType, groupBySuffix, costCenter.Id)
		}

		// Also usage incurred at the customer level
		partitionDetails = createPartitionDetailsForUsageRequest(usageRequest, partitionDetails, usageTime, activeType, groupBySuffix, usageRequest.UsageEntityId)
	default:
		// This is a search for a single cost center, return just this partition detail
		partitionDetails = createPartitionDetailsForUsageRequest(usageRequest, partitionDetails, usageTime, activeType, groupBySuffix, usageRequest.CostCenterId)
	}

	return partitionDetails, nil
}

func FromUsageChartRequestToUsagePartitionDetails(usageRequest *proto.GetUsageChartDataRequest, costCenters []*models.CostCenter, topResourceIDs []int64) ([]*models.UsagePartitionDetail, error) {
	partitionDetails := make([]*models.UsagePartitionDetail, 0)
	activeType, err := toActiveType(usageRequest.BillingPeriod)
	if err != nil {
		return nil, err
	}
	groupBySuffix, err := toGroupBySuffix(usageRequest.GroupBy)
	if err != nil {
		return nil, err
	}

	usageTime := models.NewUsageTime().WithYear(usageRequest.Year).WithMonthInt(usageRequest.Month).WithDay(int(usageRequest.Day)).WithHour(int(usageRequest.Hour))

	if usageRequest.CostCenterId != "" {
		if usageRequest.CostCenterId == "none" {
			// This is a search for data not associated with a cost center
			partitionDetails = createPartitionDetailsForUsageChart(usageRequest, partitionDetails, usageTime, activeType, groupBySuffix, usageRequest.UsageEntityId, topResourceIDs)
			return partitionDetails, nil
		} else {
			// This is a search for a single cost center
			partitionDetails = createPartitionDetailsForUsageChart(usageRequest, partitionDetails, usageTime, activeType, groupBySuffix, usageRequest.CostCenterId, topResourceIDs)
			return partitionDetails, nil
		}
	}

	// All usage incurred in all cost centers
	for _, costCenter := range costCenters {
		partitionDetails = createPartitionDetailsForUsageChart(usageRequest, partitionDetails, usageTime, activeType, groupBySuffix, costCenter.Id, topResourceIDs)
	}

	// All usage incurred at the customer level
	partitionDetails = createPartitionDetailsForUsageChart(usageRequest, partitionDetails, usageTime, activeType, groupBySuffix, usageRequest.UsageEntityId, topResourceIDs)
	return partitionDetails, nil
}

func FromPaginatedUsageRequestToUsagePartitionDetail(paginatedUsageRequest *proto.GetPaginatedUsageRequest, costCenters []*models.CostCenter) ([]*models.UsagePartitionDetail, error) {
	activeType, err := toActiveType(paginatedUsageRequest.BillingPeriod)
	if err != nil {
		return nil, err
	}
	groupBySuffix, err := toGroupBySuffix(paginatedUsageRequest.GroupBy)
	if err != nil {
		return nil, err
	}

	usageTime := models.NewUsageTime().WithYear(paginatedUsageRequest.Year).WithMonthInt(paginatedUsageRequest.Month).WithDay(int(paginatedUsageRequest.Day)).WithHour(int(paginatedUsageRequest.Hour))

	partitionDetails := make([]*models.UsagePartitionDetail, 0)
	switch paginatedUsageRequest.CostCenterId {
	case "none":
		// This is a search for data not associated with a cost center, return just this partition detail
		partitionDetails = createPartitionDetailsForPaginatedUsage(paginatedUsageRequest, partitionDetails, usageTime, activeType, groupBySuffix, paginatedUsageRequest.UsageEntityId)
	case "All", "":
		// All usage incurred in all cost centers
		for _, costCenter := range costCenters {
			partitionDetails = createPartitionDetailsForPaginatedUsage(paginatedUsageRequest, partitionDetails, usageTime, activeType, groupBySuffix, costCenter.Id)
		}

		// Also usage incurred at the customer level
		partitionDetails = createPartitionDetailsForPaginatedUsage(paginatedUsageRequest, partitionDetails, usageTime, activeType, groupBySuffix, paginatedUsageRequest.UsageEntityId)
	default:
		// This is a search for a single cost center, return just this partition detail
		partitionDetails = createPartitionDetailsForPaginatedUsage(paginatedUsageRequest, partitionDetails, usageTime, activeType, groupBySuffix, paginatedUsageRequest.CostCenterId)
	}

	return partitionDetails, nil
}

func FromRepoUsageRequestToUsagePartitionDetail(repoRequest *proto.GetRepoUsageRequest) (*models.UsagePartitionDetail, error) {
	activeType, err := toActiveType(repoRequest.BillingPeriod)
	if err != nil {
		return nil, err
	}

	byOrgRepoGroupBy, err := toGroupBySuffix(proto.UsageGroupBy_GroupByOrganization)
	if err != nil {
		return nil, err
	}

	usageTime := models.NewUsageTime().WithYear(repoRequest.Year).WithMonthInt(repoRequest.Month).WithDay(int(repoRequest.Day)).WithHour(int(repoRequest.Hour))

	return &models.UsagePartitionDetail{
		UsageEntityId: repoRequest.UsageEntityId,
		UsageTime:     usageTime,
		ActiveType:    activeType,
		GroupBy:       byOrgRepoGroupBy,
	}, nil
}

func FromUsageReportRequestToUsagePartitionDetail(usageRequest *proto.GetUsageReportRequest) (*models.UsagePartitionDetail, error) {
	activeType, err := toActiveType(usageRequest.BillingPeriod)
	if err != nil {
		return nil, err
	}

	byOrgRepoProductSkuGroupBy, err := toGroupBySuffix(proto.UsageGroupBy_GroupByOrgRepoProductSku)
	if err != nil {
		return nil, err
	}

	usageTime := models.NewUsageTime().WithYear(usageRequest.Year).WithMonthInt(usageRequest.Month).WithDay(int(usageRequest.Day)).WithHour(int(usageRequest.Hour))

	return &models.UsagePartitionDetail{
		UsageEntityId: usageRequest.UsageEntityId,
		UsageTime:     usageTime,
		ActiveType:    activeType,
		GroupBy:       byOrgRepoProductSkuGroupBy,
	}, nil
}

func GetPartitionDetailForItemDiscountLookup(item *models.Item) (*models.UsagePartitionDetail, error) {
	activeType := models.Daily

	return &models.UsagePartitionDetail{
		UsageEntityId: item.GetCustomerId(),
		UsageTime:     &item.UsageAt,
		ActiveType:    activeType,
		Sku:           item.GetSku(),
	}, nil
}

func (api *UsageApi) FromTopOrgRepoProtoToUsageRequest(input *proto.TopOrgRepoUsageRequest) *models.UsageRequest {
	return &models.UsageRequest{
		CustomerId:    input.CustomerId,
		CostCenterId:  input.CostCenterId,
		Limit:         input.Limit,
		Year:          input.Year,
		Month:         input.Month,
		Day:           input.Day,
		Hour:          input.Hour,
		BillingPeriod: input.BillingPeriod,
		FilteredOrgs:  input.OrganizationIds,
		GroupBy:       input.GroupBy,
	}
}

func (api *UsageApi) FromUsageChartDataProtoToUsageRequest(input *proto.GetUsageChartDataRequest, limit int32, logger log.Logger) (*models.UsageRequest, error) {
	customerId, err := strconv.ParseInt(input.UsageEntityId, 10, 64)
	if err != nil {
		logger.Error(
			"failed to parse customer ID",
			kvp.String("customerID", input.UsageEntityId),
		)
		return &models.UsageRequest{}, errors.Wrap(err, "failed to parse customer ID")
	}

	organizationIDs := make([]int64, 0)
	for _, orgId := range input.FilteredOrgs {
		organizationId, err := strconv.ParseInt(orgId, 10, 64)
		if err != nil {
			logger.Error(
				"failed to parse organization ID",
				kvp.String("organizationID", orgId),
			)
			return &models.UsageRequest{}, errors.Wrap(err, "failed to parse organization ID")
		}
		organizationIDs = append(organizationIDs, organizationId)
	}

	return &models.UsageRequest{
		CustomerId:    customerId,
		CostCenterId:  input.CostCenterId,
		Limit:         limit,
		Year:          input.Year,
		Month:         input.Month,
		Day:           input.Day,
		Hour:          input.Hour,
		BillingPeriod: input.BillingPeriod,
		GroupBy:       input.GroupBy,
		Product:       input.Product,
		Sku:           input.Sku,
		RepoId:        input.RepoId,
		OrgId:         input.OrgId,
		FilteredOrgs:  organizationIDs,
	}, nil
}

func BuildPartitionDetailsForTopOrgRepoUsageRequest(usageRequest *proto.TopOrgRepoUsageRequest, costCenters []*models.CostCenter, topResourceIDs []int64) ([]*models.UsagePartitionDetail, []*models.UsagePartitionDetail, error) {
	isOrgAdminRequest := len(usageRequest.OrganizationIds) > 0
	topUsagePartitionDetails := make([]*models.UsagePartitionDetail, 0)
	allUsagePartitionDetails := make([]*models.UsagePartitionDetail, 0)

	for _, resourceID := range topResourceIDs {
		// Get usage of the repo/org from each cost center - this resource could have moved between cost centers,
		// so we check the existence of a usage partition with the repo/org in each cost center
		for _, costCenter := range costCenters {
			partitionDetail, err := FromTopOrgRepoUsageRequestToUsagePartitionDetail(resourceID, usageRequest, costCenter.Id)
			if err != nil {
				return nil, nil, err
			}

			topUsagePartitionDetails = append(topUsagePartitionDetails, partitionDetail)
		}

		// Get usage of the top repo/org from parent enterprise
		partitionDetail, err := FromTopOrgRepoUsageRequestToUsagePartitionDetail(resourceID, usageRequest, fmt.Sprintf("%d", usageRequest.CustomerId))
		if err != nil {
			return nil, nil, err
		}

		topUsagePartitionDetails = append(topUsagePartitionDetails, partitionDetail)
	}

	// only query all usage if len of top resources is the same as our limit as there will be no need
	// to calculate the "other" usage if there are fewer than our limits resources
	if len(topResourceIDs) == int(usageRequest.Limit) {
		// for organization admins, we want the "all" usage to be the sum of all usage from the orgs they are admin of
		if isOrgAdminRequest {
			for _, orgId := range usageRequest.OrganizationIds {
				for _, costCenter := range costCenters {
					partitionDetail, err := FromOrgAdminTopOrgRepoUsageRequestToUsagePartitionDetailForOthers(usageRequest, costCenter.Id, orgId)
					if err != nil {
						return nil, nil, err
					}

					allUsagePartitionDetails = append(allUsagePartitionDetails, partitionDetail)
				}

				partitionDetail, err := FromOrgAdminTopOrgRepoUsageRequestToUsagePartitionDetailForOthers(usageRequest, fmt.Sprintf("%d", usageRequest.CustomerId), orgId)
				if err != nil {
					return nil, nil, err
				}

				allUsagePartitionDetails = append(allUsagePartitionDetails, partitionDetail)
			}
		} else {
			// Get all usage from all cost centers
			for _, costCenter := range costCenters {
				partitionDetail, err := FromTopOrgRepoUsageRequestToUsagePartitionDetailForOthers(usageRequest, costCenter.Id)
				if err != nil {
					return nil, nil, err
				}

				allUsagePartitionDetails = append(allUsagePartitionDetails, partitionDetail)
			}

			// Get all usage from parent enterprise
			partitionDetail, err := FromTopOrgRepoUsageRequestToUsagePartitionDetailForOthers(usageRequest, fmt.Sprintf("%d", usageRequest.CustomerId))
			if err != nil {
				return nil, nil, err
			}

			allUsagePartitionDetails = append(allUsagePartitionDetails, partitionDetail)
		}
	}

	return topUsagePartitionDetails, allUsagePartitionDetails, nil
}

func toActiveType(billingPeriod proto.BillingPeriod) (models.ActiveType, error) {
	var period models.ActiveType
	switch billingPeriod {
	case proto.BillingPeriod_Hourly:
		period = models.Hourly
	case proto.BillingPeriod_Daily:
		period = models.Daily
	case proto.BillingPeriod_Monthly:
		period = models.Monthly
	case proto.BillingPeriod_Yearly:
		period = models.Yearly
	default:
		return models.Unknown, fmt.Errorf("invalid period type %s", billingPeriod)
	}
	return period, nil
}

func toGroupBySuffix(groupBy proto.UsageGroupBy) (string, error) {
	switch groupBy {
	case proto.UsageGroupBy_GroupByProduct:
		return "byProductSku", nil
	case proto.UsageGroupBy_GroupBySku:
		return "byProductSku", nil
	case proto.UsageGroupBy_GroupByOrganization:
		return "byOrgAndRepo", nil
	case proto.UsageGroupBy_GroupByRepository:
		return "byOrgAndRepo", nil
	case proto.UsageGroupBy_GroupByOrgRepoProductSku:
		return "byOrgRepoProductSku", nil
	case proto.UsageGroupBy_GroupByCostCenter:
		return "byCostCenter", nil
	case proto.UsageGroupBy_NoGroupBy:
		return "", nil

	default:
		return "", fmt.Errorf("invalid GroupBy type %s", groupBy)
	}
}

func createPartitionDetailsForUsageChart(usageRequest *proto.GetUsageChartDataRequest, partitionDetails []*models.UsagePartitionDetail, usageTime *models.UsageTime, activeType models.ActiveType, groupBySuffix string, usageEntityId string, topResourceIDs []int64) []*models.UsagePartitionDetail {
	isOrgAdminRequest := len(usageRequest.FilteredOrgs) > 0

	// If an allowlist of orgs is passed in, we need to construct partition details with each org in the list.
	if isOrgAdminRequest {
		// First check if an org id is passed in, and if that org id is in the list of filtered orgs
		if usageRequest.OrgId > 0 {
			if slices.Contains(usageRequest.FilteredOrgs, strconv.Itoa(int(usageRequest.OrgId))) {
				partitionDetail := &models.UsagePartitionDetail{
					UsageEntityId: usageEntityId,
					Product:       usageRequest.Product,
					Sku:           usageRequest.Sku,
					UsageTime:     usageTime,
					ActiveType:    activeType,
					RepoId:        usageRequest.RepoId,
					OrgId:         usageRequest.OrgId,
					GroupBy:       groupBySuffix,
					IsOrgAdmin:    true,
				}
				partitionDetails = append(partitionDetails, partitionDetail)
			}
		} else {
			// top resource IDs for org admin requests are already scoped to the org admins orgs so we just need
			// to build the partition detail to hit the repo usage partition
			if usageRequest.GroupBy == proto.UsageGroupBy_GroupByRepository && len(topResourceIDs) > 0 {
				for _, topRepositoryId := range topResourceIDs {
					partitionDetail := &models.UsagePartitionDetail{
						UsageEntityId: usageEntityId,
						Product:       usageRequest.Product,
						Sku:           usageRequest.Sku,
						UsageTime:     usageTime,
						ActiveType:    activeType,
						RepoId:        topRepositoryId,
						GroupBy:       groupBySuffix,
						IsOrgAdmin:    true,
					}
					partitionDetails = append(partitionDetails, partitionDetail)
				}
			} else {
				for i := 0; i < len(usageRequest.FilteredOrgs); i++ {
					orgId, _ := strconv.Atoi(usageRequest.FilteredOrgs[i])
					partitionDetail := &models.UsagePartitionDetail{
						UsageEntityId: usageEntityId,
						Product:       usageRequest.Product,
						Sku:           usageRequest.Sku,
						UsageTime:     usageTime,
						ActiveType:    activeType,
						RepoId:        usageRequest.RepoId,
						OrgId:         int64(orgId),
						GroupBy:       groupBySuffix,
						IsOrgAdmin:    true,
					}
					partitionDetails = append(partitionDetails, partitionDetail)
				}
			}
		}
	} else {
		switch {
		case usageRequest.GroupBy == proto.UsageGroupBy_GroupByRepository && len(topResourceIDs) > 0:
			for _, topRepositoryId := range topResourceIDs {
				partitionDetail := &models.UsagePartitionDetail{
					UsageEntityId: usageEntityId,
					Product:       usageRequest.Product,
					Sku:           usageRequest.Sku,
					UsageTime:     usageTime,
					ActiveType:    activeType,
					RepoId:        topRepositoryId,
					GroupBy:       groupBySuffix,
				}
				partitionDetails = append(partitionDetails, partitionDetail)
			}

			// hit the customer total usage partition which we will later use to build the "all other" line
			// if we have more than the limit of top resources
			if len(topResourceIDs) == topN {
				partitionDetail := &models.UsagePartitionDetail{
					UsageEntityId: usageEntityId,
					Product:       usageRequest.Product,
					Sku:           usageRequest.Sku,
					UsageTime:     usageTime,
					ActiveType:    activeType,
				}
				partitionDetails = append(partitionDetails, partitionDetail)
			}
		case usageRequest.GroupBy == proto.UsageGroupBy_GroupByOrganization && len(topResourceIDs) > 0:
			for _, topOrganizationId := range topResourceIDs {
				partitionDetail := &models.UsagePartitionDetail{
					UsageEntityId: usageEntityId,
					Product:       usageRequest.Product,
					Sku:           usageRequest.Sku,
					UsageTime:     usageTime,
					ActiveType:    activeType,
					OrgId:         topOrganizationId,
					GroupBy:       groupBySuffix,
				}
				partitionDetails = append(partitionDetails, partitionDetail)
			}

			// hit the customer total usage partition which we will later use to build the "all other" line
			// if we have more than the limit of top resources
			if len(topResourceIDs) == topN {
				partitionDetail := &models.UsagePartitionDetail{
					UsageEntityId: usageEntityId,
					Product:       usageRequest.Product,
					Sku:           usageRequest.Sku,
					UsageTime:     usageTime,
					ActiveType:    activeType,
				}
				partitionDetails = append(partitionDetails, partitionDetail)
			}
		default:
			partitionDetail := &models.UsagePartitionDetail{
				UsageEntityId: usageEntityId,
				Product:       usageRequest.Product,
				Sku:           usageRequest.Sku,
				UsageTime:     usageTime,
				ActiveType:    activeType,
				RepoId:        usageRequest.RepoId,
				OrgId:         usageRequest.OrgId,
				GroupBy:       groupBySuffix,
			}
			partitionDetails = append(partitionDetails, partitionDetail)
		}

	}

	return partitionDetails
}

func createPartitionDetailsForPaginatedUsage(usageRequest *proto.GetPaginatedUsageRequest, partitionDetails []*models.UsagePartitionDetail, usageTime *models.UsageTime, activeType models.ActiveType, groupBySuffix string, usageEntityId string) []*models.UsagePartitionDetail {
	partitionDetail := &models.UsagePartitionDetail{
		UsageEntityId: usageEntityId,
		UsageTime:     usageTime,
		ActiveType:    activeType,
		GroupBy:       groupBySuffix,
	}
	partitionDetails = append(partitionDetails, partitionDetail)

	return partitionDetails
}

func createPartitionDetailsForUsageRequest(usageRequest *proto.GetUsageRequest, partitionDetails []*models.UsagePartitionDetail, usageTime *models.UsageTime, activeType models.ActiveType, groupBySuffix string, usageEntityId string) []*models.UsagePartitionDetail {
	isOrgAdminRequest := len(usageRequest.OrganizationIds) > 0

	// If an allowlist of orgs is passed in, we need to construct partition details with each org in the list.
	if isOrgAdminRequest {
		// this is a temporary check as many places in dotcom still pass a byOrgRepoProductSkuGrouping for org admin requests
		// in such cases, we should overwrite the group by to be byProductSku so org admin queries hit the correct partition
		// i.e. customerID:org:orgId:usageTime:byProductSku
		groupBy := groupBySuffix
		if groupBy == models.ByOrgRepoProductSkuGrouping {
			groupBy = models.ByProductSkuGrouping
		}

		// First check if an org id is passed in, and if that org id is in the list of filtered orgs
		if usageRequest.OrgId > 0 {
			if slices.Contains(usageRequest.OrganizationIds, usageRequest.OrgId) {
				partitionDetail := &models.UsagePartitionDetail{
					UsageEntityId: usageEntityId,
					Product:       usageRequest.Product,
					Sku:           usageRequest.Sku,
					UsageTime:     usageTime,
					ActiveType:    activeType,
					RepoId:        usageRequest.RepoId,
					OrgId:         usageRequest.OrgId,
					GroupBy:       groupBy,
					IsOrgAdmin:    true,
				}
				partitionDetails = append(partitionDetails, partitionDetail)
			}
		} else {
			for _, orgId := range usageRequest.OrganizationIds {
				partitionDetail := &models.UsagePartitionDetail{
					UsageEntityId: usageEntityId,
					Product:       usageRequest.Product,
					Sku:           usageRequest.Sku,
					UsageTime:     usageTime,
					ActiveType:    activeType,
					RepoId:        usageRequest.RepoId,
					OrgId:         orgId,
					GroupBy:       groupBy,
					IsOrgAdmin:    true,
				}
				partitionDetails = append(partitionDetails, partitionDetail)
			}
		}
	} else {
		partitionDetail := &models.UsagePartitionDetail{
			UsageEntityId: usageEntityId,
			Product:       usageRequest.Product,
			Sku:           usageRequest.Sku,
			UsageTime:     usageTime,
			ActiveType:    activeType,
			RepoId:        usageRequest.RepoId,
			OrgId:         usageRequest.OrgId,
			GroupBy:       groupBySuffix,
		}
		partitionDetails = append(partitionDetails, partitionDetail)
	}

	return partitionDetails
}
