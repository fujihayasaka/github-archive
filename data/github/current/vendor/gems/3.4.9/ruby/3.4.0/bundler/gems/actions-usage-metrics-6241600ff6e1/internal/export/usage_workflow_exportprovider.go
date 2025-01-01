package export

import (
	"fmt"
	"strconv"

	"github.com/github/actions-usage-metrics/internal/projections/common"
	"github.com/github/actions-usage-metrics/lib/twirp/proto"
)

type workflowUsageExportProvider struct {
	repoMap map[int64]string
	orgMap  map[int64]string
}

func NewWorkflowUsageExportProvider(repoMap map[int64]string, orgMap map[int64]string) workflowUsageExportProvider {
	return workflowUsageExportProvider{repoMap: repoMap, orgMap: orgMap}
}

var _ ExportProvider[*proto.RepoWorkflowRunnerUsageItem] = (*workflowUsageExportProvider)(nil)

func (e workflowUsageExportProvider) GetFieldFromHeader(headerKey string, item *proto.RepoWorkflowRunnerUsageItem) (string, error) {
	switch headerKey {
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
	case string(common.WorkflowExecutionsFilterKey):
		return strconv.FormatInt(int64(item.GetWorkflowExecutions().GetCount()), 10), nil
	case string(common.JobsFilterKey):
		return strconv.FormatInt(int64(item.GetJobs().GetCount()), 10), nil
	case string(common.RunnerTypeFilterKey):
		return getRunnerTypeDisplayString(item.GetRunnerType()), nil
	case string(common.RunnerRuntimeFilterKey):
		return getRunnerRuntimeDisplayString(item.GetRunnerRuntime()), nil
	default:
		return "", fmt.Errorf("invalid header key: %s", headerKey)
	}
}
