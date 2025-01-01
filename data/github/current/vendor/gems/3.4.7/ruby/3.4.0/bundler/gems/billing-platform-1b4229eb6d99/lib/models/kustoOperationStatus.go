package models

type KustoOperationStatus string

// See the following for operation statuses: https://learn.microsoft.com/en-us/azure/data-explorer/kusto/management/show-operations
const (
	KustoOperationStatusEmpty              KustoOperationStatus = ""
	KustoOperationStatusInProgress         KustoOperationStatus = "InProgress"
	KustoOperationStatusCompleted          KustoOperationStatus = "Completed"
	KustoOperationStatusFailed             KustoOperationStatus = "Failed"
	KustoOperationStatusPartiallySucceeded KustoOperationStatus = "PartiallySucceeded"
	KustoOperationStatusAbandoned          KustoOperationStatus = "Abandoned"
	KustoOperationStatusBadInput           KustoOperationStatus = "BadInput"
	KustoOperationStatusScheduled          KustoOperationStatus = "Scheduled"
	KustoOperationStatusThrottled          KustoOperationStatus = "Throttled"
	KustoOperationStatusCanceled           KustoOperationStatus = "Canceled"
	KustoOperationStatusSkipped            KustoOperationStatus = "Skipped"
)

func (s KustoOperationStatus) String() string {
	return string(s)
}
