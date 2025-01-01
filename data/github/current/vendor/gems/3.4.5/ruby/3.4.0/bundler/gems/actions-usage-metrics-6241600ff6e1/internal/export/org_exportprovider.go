package export

import (
	"fmt"
	"strconv"

	"github.com/github/actions-usage-metrics/internal/projections/common"
	"github.com/github/actions-usage-metrics/lib/twirp/proto"
)

type orgUsageExportProvider struct {
	orgMap map[int64]string
}

func NewOrgUsageExportProvider(orgMap map[int64]string) orgUsageExportProvider {
	return orgUsageExportProvider{orgMap: orgMap}
}

var _ ExportProvider[*proto.OrgUsageItem] = (*orgUsageExportProvider)(nil)

func (e orgUsageExportProvider) GetFieldFromHeader(headerKey string, item *proto.OrgUsageItem) (string, error) {
	switch headerKey {
	case string(common.OwnerIdFilterKey):
		orgName, ok := e.orgMap[item.GetOwnerId()]
		if !ok {
			orgName = "Organization not found"
		}
		return orgName, nil
	case string(common.TotalMinutesFilterKey):
		return strconv.FormatInt(item.GetTotalMinutes(), 10), nil
	case string(common.WorkflowExecutionsFilterKey):
		return strconv.FormatInt(int64(item.GetWorkflowExecutions().GetCount()), 10), nil
	case string(common.WorkflowsFilterKey):
		return strconv.FormatInt(int64(item.GetWorkflows().GetCount()), 10), nil
	case string(common.FailureRateFilterKey):
		return strconv.FormatFloat(float64(item.GetFailureRate()), 'f', 2, 64), nil
	case string(common.AverageRunTimeFilterKey):
		return strconv.FormatInt(int64(item.GetAverageRunTime()), 10), nil
	case string(common.AverageQueueTimeFilterKey):
		return strconv.FormatInt(int64(item.GetAverageQueueTime()), 10), nil
	case string(common.JobExecutionsFilterKey):
		return strconv.FormatInt(item.GetJobExecutions(), 10), nil
	default:
		return "", fmt.Errorf("invalid header key: %s", headerKey)
	}
}
