package querybuilder

type KustoField string

// These values must match kusto table names.
const (
	JobNameFieldName                  KustoField = "jobName"
	JobUserIdentifierFieldName        KustoField = "jobUserIdentifier"
	OwnerIdFieldName                  KustoField = "repositoryOwnerId"
	RepositoryIdFieldName             KustoField = "repositoryId"
	RunnerRuntimeFieldName            KustoField = "runnerRuntime"
	RunnerLabelsFieldName             KustoField = "runnerLabels"
	RunnerLabelsAutoCompleteFieldName KustoField = "label"
	RunnerTypeFieldName               KustoField = "runnerType"
	WorkflowFileNameFieldName         KustoField = "workflowFileName"
	WorkflowFilePathFieldName         KustoField = "workflowFilePath"

	// Aggregations.
	JobExecutionsFieldName           KustoField = "jobExecutions"
	JobsCountFieldName               KustoField = "jobs"
	TotalMinutesFieldName            KustoField = "totalMinutes"
	WorkflowExecutionsCountFieldName KustoField = "workflowExecutions"
	WorkflowsCountFieldName          KustoField = "workflows"
	AverageRunTime                   KustoField = "averageRunTime"
	AverageQueueTime                 KustoField = "averageQueueTime"
	FailureRate                      KustoField = "failureRate"
)

func (f KustoField) String() string {
	return string(f)
}

func (f KustoField) IsNumeric() bool {
	_, ok := numericFields[f]
	return ok
}

func GetKustoField(s string) KustoField {
	return KustoField(s)
}

var numericFields = map[KustoField]struct{}{
	JobExecutionsFieldName:           {},
	JobsCountFieldName:               {},
	OwnerIdFieldName:                 {},
	RepositoryIdFieldName:            {},
	TotalMinutesFieldName:            {},
	WorkflowExecutionsCountFieldName: {},
	WorkflowsCountFieldName:          {},
	AverageRunTime:                   {},
	AverageQueueTime:                 {},
	FailureRate:                      {},
}

type OrderBy struct {
	Field     KustoField
	Direction OrderByDirection
}

type OffsetLimit struct {
	Offset uint64
	Limit  uint64
}

type OrderByDirection int

const (
	OrderByDirection_ASC  = 1
	OrderByDirection_DESC = 2
)
