package azp

import (
	"context"
	"time"
)

type ChecksClient interface {
	StepsFromChangeID(ctx context.Context, changeID int64, jobID string, planID string) ([]*ChangeIDResponseSteps, error)
	StepsFromChangeIDForRun(ctx context.Context, changeID int64, planID string, onlyInProgressJobs bool) ([]*ChangeIDResponseJobSteps, error)
}

type ChangeIDResponse struct {
	Steps []*ChangeIDResponseSteps `json:"steps"`
}

type ChangeIDResponseForRun struct {
	Jobs []*ChangeIDResponseJobSteps `json:"jobs"`
}

type ChangeIDResponseSteps struct {
	// The record id (GUID) of a step in actions service. this is external_id in dotcom context
	ID string `json:"id,omitempty"`
	// The step name
	Name string `json:"name,omitempty"`
	// The step status ("all|cancelling|completed|inProgress|none|notStarted|postponed|pending")
	Status string `json:"status,omitempty"`
	// The step conclusion ("succeeded|failed|canceled|skipped|none|partiallySucceeded")
	Conclusion string `json:"conclusion,omitempty"`
	// When this step was started
	StartedAt *time.Time `json:"started_at,omitempty"`
	// When this step was finished
	CompletedAt *time.Time `json:"completed_at,omitempty"`
	// Log entry for the step
	Log *ChangeIDResponseStepLog `json:"log,omitempty"`
	// The changeID of the step
	ChangeID int64 `json:"changeId,omitempty"`
	// The step number
	Number int64 `json:"number,omitempty"`
}

type ChangeIDResponseJobSteps struct {
	// The record id (GUID) of a job in actions service. this is external_id in dotcom context
	ID string `json:"id,omitempty"`
	// The changeID of the job
	ChangeID int64 `json:"changeId,omitempty"`
	// The steps of the job
	Steps []*ChangeIDResponseSteps `json:"steps,omitempty"`
}

func (s ChangeIDResponseSteps) IsStarted() bool {
	if s.StartedAt == nil {
		return false
	}

	return !s.StartedAt.IsZero()
}

type ChangeIDResponseStepLog struct {
	// The id of the log
	ID int64 `json:"id,omitempty"`
	// The url of the log
	URL string `json:"url,omitempty"`
	// The number of lines in the completed log
	LineCount int64 `json:"lineCount,omitempty"`
}
