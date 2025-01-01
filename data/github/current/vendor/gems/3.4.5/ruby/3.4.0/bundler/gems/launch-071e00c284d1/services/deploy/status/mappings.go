package status

import (
	"github.com/github/launch/workflowbuild/azp/azptypes"
)

type statusName string
type resultName string

const (
	statusInProgress statusName = "IN_PROGRESS"
	statusCompleted  statusName = "COMPLETED"
	statusQueued     statusName = "QUEUED"
	statusPending    statusName = "PENDING"
	resultCancelled  resultName = "CANCELLED"
	resultSkipped    resultName = "SKIPPED"
	resultFailure    resultName = "FAILURE"
	resultSuccess    resultName = "SUCCESS"
	resultNeutral    resultName = "NEUTRAL"
)

func AZPToCheckStatus(in string) statusName {
	switch in {
	case azptypes.StatusCancelling:
		return getStatusName(Status_STATUS_CANCELLING)
	case azptypes.StatusCompleted:
		return getStatusName(Status_STATUS_COMPLETED)
	case azptypes.StatusInProgress, azptypes.StatusThrottled:
		return getStatusName(Status_STATUS_IN_PROGRESS)
	case azptypes.StatusNone:
		return getStatusName(Status_STATUS_NONE)
	case azptypes.StatusNotStarted:
		return getStatusName(Status_STATUS_NOT_STARTED)
	case azptypes.StatusPending:
		return getStatusName(Status_STATUS_PENDING)
	default:
		return getStatusName(-1)
	}
}

func getStatusName(in Status) statusName {
	switch in {
	case Status_STATUS_ALL, Status_STATUS_CANCELLING, Status_STATUS_IN_PROGRESS: // TODO: what is ALL??
		return statusInProgress
	case Status_STATUS_COMPLETED:
		return statusCompleted
	case Status_STATUS_PENDING:
		return statusPending
	case Status_STATUS_NONE, Status_STATUS_POSTPONED, Status_STATUS_NOT_STARTED: // TODO: what is NONE?
		return statusQueued
	default:
		return statusInProgress // It is an enum so should not get here
	}
}

func AZPToCheckResult(in string) resultName {
	switch in {
	case azptypes.ResultCanceled:
		return getResultName(Result_RESULT_CANCELED)
	case azptypes.ResultFailed:
		return getResultName(Result_RESULT_FAILED)
	case azptypes.ResultNone:
		return resultNeutral
	case azptypes.ResultSkipped:
		return getResultName(Result_RESULT_SKIPPED)
	case azptypes.ResultPartiallySucceeded:
		return getResultName(Result_RESULT_PARTIALLY_SUCCEEDED)
	case azptypes.ResultSucceeded:
		return getResultName(Result_RESULT_SUCCEEDED)
	default:
		return getResultName(-1)
	}
}

func getResultName(in Result) resultName {
	switch in {
	case Result_RESULT_CANCELED:
		return resultCancelled
	case Result_RESULT_SKIPPED:
		return resultSkipped
	case Result_RESULT_FAILED:
		return resultFailure
	case Result_RESULT_PARTIALLY_SUCCEEDED, Result_RESULT_SUCCEEDED:
		return resultSuccess
	default:
		return resultNeutral
	}
}
