package github

type CheckRunStatus string
type CheckRunConclusion string
type CheckStepStatus string
type CheckStepConclusion string
type CheckSuiteStatus string
type CheckSuiteConclusion string
type CheckSuiteAuthorAssociation string

const (
	CheckRunQueuedStatus     CheckRunStatus = "QUEUED"
	CheckRunInProgressStatus CheckRunStatus = "IN_PROGRESS"
	CheckRunCompletedStatus  CheckRunStatus = "COMPLETED"

	CheckRunNotConcluded        CheckRunConclusion = ""
	CheckRunSuccessConclusion   CheckRunConclusion = "SUCCESS"
	CheckRunTimedOutConclusion  CheckRunConclusion = "TIMED_OUT"
	CheckRunFailedConclusion    CheckRunConclusion = "FAILURE"
	CheckRunCancelledConclusion CheckRunConclusion = "CANCELLED"
	CheckRunNeutralConclusion   CheckRunConclusion = "NEUTRAL"
	CheckRunSkippedConclusion   CheckRunConclusion = "SKIPPED"

	CheckStepCompletedStatus  CheckStepStatus = "COMPLETED" // Not yet needed: QUEUED, and REQUESTED
	CheckStepInProgressStatus CheckStepStatus = "IN_PROGRESS"

	CheckStepSuccessConclusion  CheckStepConclusion = "SUCCESS" // Not yet needed: ACTION_REQUIRED, CANCELLED, FAILURE, SKIPPED, STALE
	CheckStepTimedOutConclusion CheckStepConclusion = "TIMED_OUT"
	CheckStepNeutralConclusion  CheckStepConclusion = "NEUTRAL"

	CheckSuiteQueuedStatus     CheckSuiteStatus = "QUEUED"
	CheckSuiteInProgressStatus CheckSuiteStatus = "IN_PROGRESS"
	CheckSuiteCompletedStatus  CheckSuiteStatus = "COMPLETED"

	NilCheckSuiteConclusion            CheckSuiteConclusion = ""
	CheckSuiteNeutralConclusion        CheckSuiteConclusion = "neutral"
	CheckSuiteSuccessConclusion        CheckSuiteConclusion = "success"
	CheckSuiteFailureConclusion        CheckSuiteConclusion = "failure"
	CheckSuiteCancelledConclusion      CheckSuiteConclusion = "cancelled"
	CheckSuiteActionRequiredConclusion CheckSuiteConclusion = "action_required"
	CheckSuiteTimedOutConclusion       CheckSuiteConclusion = "timed_out"
	CheckSuiteSkippedConclusion        CheckSuiteConclusion = "skipped"
	CheckSuiteStaleConclusion          CheckSuiteConclusion = "stale"
	CheckSuiteStartupFailureConclusion CheckSuiteConclusion = "startup_failure"
)

func (c CheckSuiteConclusion) String() string {
	return string(c)
}
