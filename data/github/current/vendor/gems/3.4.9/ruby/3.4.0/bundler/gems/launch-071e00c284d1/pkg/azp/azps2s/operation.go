package azps2s

import (
	"context"
	"strings"
	"time"
)

const (
	// Possible values for OperationStatus
	// https://docs.microsoft.com/en-us/rest/api/azure/devops/operations/operations/get?view=azure-devops-rest-5.0#operationstatus
	OperationCancelled = "cancelled"

	OperationFailed = "failed"

	OperationInProgress = "inProgress"

	OperationUnknown = "notSet"

	OperationQueued = "queued"

	OperationSucceeded = "succeeded"
)

type OperationResponse struct {
	ID     string `json:"id"`
	Status string `json:"status"`
	URL    string `json:"url"`
	Result string `json:"resultMessage"`
}

type OperationResult struct {
	Operation *OperationResponse
	RawBody   string
}

type OperationsClient interface {
	WaitForCompletion(context.Context, string, time.Duration, time.Duration) (OperationResponse, error)
}

func (op OperationResult) IsComplete() bool {
	return strings.EqualFold(op.Operation.Status, OperationCancelled) ||
		strings.EqualFold(op.Operation.Status, OperationFailed) ||
		strings.EqualFold(op.Operation.Status, OperationSucceeded)
}
