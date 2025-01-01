package common

import (
	"fmt"
	"strconv"

	"github.com/github/actions-usage-metrics/internal/querybuilder"
	"github.com/github/actions-usage-metrics/lib/twirp/proto"
)

type FilterConverter struct{}

type FilterKey string

const (
	AverageRunTimeFilterKey     FilterKey = "average_run_time"
	AverageQueueTimeFilterKey   FilterKey = "average_queue_time"
	FailureRateFilterKey        FilterKey = "failure_rate"
	JobExecutionsFilterKey      FilterKey = "job_executions"
	JobNameFilterKey            FilterKey = "job_name"
	JobsFilterKey               FilterKey = "jobs"
	JobUserIdentifierFilterKey  FilterKey = "job_user_identifier"
	OwnerId                     FilterKey = "owner_id"
	RepositoryIdFilterKey       FilterKey = "repository_id"
	RunnerRuntimeFilterKey      FilterKey = "runner_runtime"
	RunnerLabelsFilterKey       FilterKey = "runner_labels"
	RunnerTypeFilterKey         FilterKey = "runner_type"
	TotalMinutesFilterKey       FilterKey = "total_minutes"
	WorkflowExecutionsFilterKey FilterKey = "workflow_executions"
	WorkflowFileNameFilterKey   FilterKey = "workflow_file_name"
	WorkflowFilePathFilterKey   FilterKey = "workflow_file_path"
	WorkflowsFilterKey          FilterKey = "workflows"
)

var filterKeyToKustoFieldMap = map[string]querybuilder.KustoField{
	// Map from proto key to kusto model field
	"text":                              querybuilder.WorkflowFileNameFieldName, // Alias for workflow_file_name
	string(AverageRunTimeFilterKey):     querybuilder.AverageRunTime,
	string(AverageQueueTimeFilterKey):   querybuilder.AverageQueueTime,
	string(FailureRateFilterKey):        querybuilder.FailureRate,
	string(JobExecutionsFilterKey):      querybuilder.JobExecutionsFieldName,
	string(JobNameFilterKey):            querybuilder.JobNameFieldName,
	string(JobsFilterKey):               querybuilder.JobsCountFieldName,
	string(JobUserIdentifierFilterKey):  querybuilder.JobUserIdentifierFieldName,
	string(OwnerId):                     querybuilder.OwnerIdFieldName,
	string(RepositoryIdFilterKey):       querybuilder.RepositoryIdFieldName,
	string(RunnerRuntimeFilterKey):      querybuilder.RunnerRuntimeFieldName,
	string(RunnerLabelsFilterKey):       querybuilder.RunnerLabelsFieldName,
	string(RunnerTypeFilterKey):         querybuilder.RunnerTypeFieldName,
	string(TotalMinutesFilterKey):       querybuilder.TotalMinutesFieldName,
	string(WorkflowExecutionsFilterKey): querybuilder.WorkflowExecutionsCountFieldName,
	string(WorkflowFileNameFilterKey):   querybuilder.WorkflowFileNameFieldName,
	string(WorkflowFilePathFilterKey):   querybuilder.WorkflowFilePathFieldName,
	string(WorkflowsFilterKey):          querybuilder.WorkflowsCountFieldName,
}

var filterKeyIsNumericalInCsvMap = map[string]bool{
	// Map from proto key to kusto model field
	"text":                              false,
	string(AverageRunTimeFilterKey):     true,
	string(AverageQueueTimeFilterKey):   true,
	string(FailureRateFilterKey):        true,
	string(JobExecutionsFilterKey):      true,
	string(JobNameFilterKey):            false,
	string(JobsFilterKey):               true,
	string(JobUserIdentifierFilterKey):  false,
	string(RepositoryIdFilterKey):       false,
	string(RunnerRuntimeFilterKey):      false,
	string(RunnerTypeFilterKey):         false,
	string(TotalMinutesFilterKey):       true,
	string(WorkflowExecutionsFilterKey): true,
	string(WorkflowFileNameFilterKey):   false,
	string(WorkflowFilePathFilterKey):   false,
	string(WorkflowsFilterKey):          true,
}

var filterKeyIsUnsupportedForSummaryInWorkflowMap = map[string]bool{
	// Map from proto key to kusto model field
	"text":                              true,
	string(JobsFilterKey):               true,
	string(WorkflowExecutionsFilterKey): true,
}

func (fc *FilterConverter) Convert(protoFilter *proto.Filter) (querybuilder.KustoModelFilter, error) {
	kustoField, ok := filterKeyToKustoFieldMap[protoFilter.Key]
	if !ok {
		return querybuilder.KustoModelFilter{}, fmt.Errorf("invalid filter key: %s", protoFilter.Key)
	}

	// Proto filter values are always strings, so we need to convert them to the correct type
	var values []any
	if kustoField.IsNumeric() {
		for _, val := range protoFilter.Values {
			numVal, err := strconv.ParseFloat(val, 64) // convert to float instead of int because float also supports int, but int does not support float
			if err != nil {
				return querybuilder.KustoModelFilter{}, err
			}
			values = append(values, numVal)
		}
	} else {
		for _, val := range protoFilter.Values {
			values = append(values, val)
		}
	}

	return querybuilder.KustoModelFilter{
		Field:    kustoField,
		Operator: protoFilter.Operator,
		Values:   values,
	}, nil
}

func IsNumericalColumnInCsv(key string) bool {
	isNumerical, ok := filterKeyIsNumericalInCsvMap[key]
	if !ok {
		return false
	}

	return isNumerical
}

func FilterIsUnsupportForSummaryInWorkflows(key string) bool {
	unsupported, ok := filterKeyIsUnsupportedForSummaryInWorkflowMap[key]

	if !ok {
		return false
	}

	return unsupported
}
