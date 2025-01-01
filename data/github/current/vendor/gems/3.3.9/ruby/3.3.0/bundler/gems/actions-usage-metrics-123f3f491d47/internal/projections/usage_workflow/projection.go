package usage_workflow

import (
	"github.com/Azure/azure-kusto-go/azkustodata/kql"
	"github.com/github/actions-usage-metrics/internal/projections/common"
	"github.com/github/actions-usage-metrics/internal/versioning"
	"github.com/github/actions-usage-metrics/lib/twirp/proto"
)

type RepoWorkflowRunnerItem struct {
	// Grouping
	RepositoryId     int64  `json:"repositoryId" kusto:"repositoryId"`
	WorkflowFilePath string `json:"workflowFilePath" kusto:"workflowFilePath"`
	RunnerType       string `json:"runnerType" kusto:"runnerType"`
	RunnerRuntime    string `json:"runnerRuntime" kusto:"runnerRuntime"`

	// Workflow name (for filtering and autocomplete)
	WorkflowFileName string `json:"workflowFileName" kusto:"workflowFileName"`

	// Aggregations
	TotalFailureMinutes int64 `json:"totalFailureMinutes" kusto:"totalFailureMinutes"`
	TotalMinutes        int64 `json:"totalMinutes" kusto:"totalMinutes"`

	WorkflowExecutions int64 `kusto:"workflowExecutions"`
	Jobs               int64 `kusto:"jobs"`
}

type repoWorkflowRunnerProjection struct {
	version versioning.Version
	scope   *proto.Scope
}

func RepoWorkflowRunnerProjection(version versioning.Version, scope *proto.Scope) common.ProjectionInfo {
	return repoWorkflowRunnerProjection{version, scope}
}

var _ common.Projection[RepoWorkflowRunnerItem] = &repoWorkflowRunnerProjection{}

const ProjectionName = common.ProjectionName_ActionsWorkflowUsage

func (repoWorkflowRunnerProjection) Name() common.ProjectionName   { return ProjectionName }
func (p repoWorkflowRunnerProjection) Version() versioning.Version { return p.version }

func (p repoWorkflowRunnerProjection) KustoTableOrView(aggInterval common.ProjectionAggregationInterval) common.KustoTableOrView {
	return common.GetKustoTableOrView(common.WorkflowsTableType, aggInterval, p.version, p.scope, true)
}

func (p repoWorkflowRunnerProjection) KustoQuery() *kql.Builder {
	return kql.New(`
		| extend workflowFilePath=base64_decode_tostring(workflowFilePath)
		| summarize
        totalMinutes=sum(totalMinutes),
		totalFailureMinutes=sum(totalFailureMinutes),
        workflowExecutions=dcount_hll(hll_merge(workflowRunHll)),
        jobs=dcount_hll(hll_merge(jobUserIdentifierHll))
        by
        repositoryOwnerId,
        repositoryId,
        workflowFilePath,
        workflowFileName=tostring(split(workflowFilePath, "/")[-1]),
        runnerType,
        runnerRuntime
	`)
}

func (p repoWorkflowRunnerProjection) KustoSummarize() *kql.Builder {
	return kql.New("")
}
