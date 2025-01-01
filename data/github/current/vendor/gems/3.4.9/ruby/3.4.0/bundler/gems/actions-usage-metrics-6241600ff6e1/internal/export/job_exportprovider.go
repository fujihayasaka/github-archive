package export

import (
	"fmt"
	"strconv"

	"github.com/github/actions-usage-metrics/internal/projections/common"
	"github.com/github/actions-usage-metrics/lib/twirp/proto"
)

type jobUsageExportProvider struct {
	repoMap map[int64]string
	orgMap  map[int64]string
}

func NewJobUsageExportProvider(repoMap map[int64]string, orgMap map[int64]string) jobUsageExportProvider {
	return jobUsageExportProvider{repoMap: repoMap, orgMap: orgMap}
}

var _ ExportProvider[*proto.JobUsageItem] = (*jobUsageExportProvider)(nil)

func (e jobUsageExportProvider) GetFieldFromHeader(headerKey string, item *proto.JobUsageItem) (string, error) {
	switch headerKey {
	case string(common.JobNameFilterKey):
		return item.GetJobName(), nil
	case string(common.WorkflowFilePathFilterKey):
		return item.GetWorkflowFilePath(), nil
	case string(common.RepositoryIdFilterKey):
		repoName, ok := e.repoMap[item.GetRepositoryId()]
		if !ok {
			repoName = "Repository not found"
		}
		return repoName, nil
	case string(common.OwnerIdFilterKey):
		orgName, ok := e.orgMap[item.GetOwnerId()]
		if !ok {
			orgName = "Organization not found"
		}
		return orgName, nil
	case string(common.TotalMinutesFilterKey):
		return strconv.FormatInt(item.GetTotalMinutes(), 10), nil
	case string(common.JobExecutionsFilterKey):
		return strconv.FormatInt(item.GetJobExecutions(), 10), nil
	case string(common.RunnerTypeFilterKey):
		return getRunnerTypeDisplayString(item.GetRunnerType()), nil
	case string(common.RunnerRuntimeFilterKey):
		return getRunnerRuntimeDisplayString(item.GetRunnerRuntime()), nil
	case string(common.RunnerLabelsFilterKey):
		return item.GetRunnerLabels(), nil
	case string(common.FailureRateFilterKey):
		return strconv.FormatFloat(float64(item.GetFailureRate()), 'f', 2, 64), nil
	case string(common.AverageRunTimeFilterKey):
		return strconv.FormatInt(int64(item.GetAverageRunTime()), 10), nil
	case string(common.AverageQueueTimeFilterKey):
		return strconv.FormatInt(int64(item.GetAverageQueueTime()), 10), nil
	default:
		return "", fmt.Errorf("invalid header key: %s", headerKey)
	}
}
