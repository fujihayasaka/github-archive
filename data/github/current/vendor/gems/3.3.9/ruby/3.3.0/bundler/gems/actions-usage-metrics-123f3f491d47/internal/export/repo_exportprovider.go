package export

import (
	"fmt"
	"strconv"

	"github.com/github/actions-usage-metrics/internal/projections/common"
	"github.com/github/actions-usage-metrics/lib/twirp/proto"
)

type repoUsageExportProvider struct {
	repoMap map[int64]string
}

func NewRepoUsageExportProvider(repoMap map[int64]string) repoUsageExportProvider {
	return repoUsageExportProvider{repoMap: repoMap}
}

var _ ExportProvider[*proto.RepoUsageItem] = (*repoUsageExportProvider)(nil)

func (e repoUsageExportProvider) GetFieldFromHeader(headerKey string, item *proto.RepoUsageItem) (string, error) {
	switch headerKey {
	case string(common.RepositoryIdFilterKey):
		repoName, ok := e.repoMap[item.GetRepositoryId()]
		if !ok {
			repoName = "Repository not found"
		}
		return repoName, nil
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
