package jobs

import (
	"github.com/Azure/azure-sdk-for-go/sdk/azcore"
	"github.com/github/sweagentd/internal/jobs/command"
)

// JobSummary is a subset of the job fields that is used to summarize a job in
// some database (read) operations. It is used to reduce the amount of data that
// needs to be transferred over the network for operations that do not require
// the full job details.
type JobSummary struct {
	ID           string       `json:"id"`
	RepoID       int64        `json:"repo_id"`
	OwnerID      int64        `json:"owner_id"`
	AssignmentID string       `json:"assignment_id"`
	ComputeID    string       `json:"compute_id"`
	SessionID    string       `json:"session_id"`
	Status       JobStatus    `json:"status"`
	CreatedAt    int64        `json:"created_at"`
	QueuedAt     int64        `json:"queued_at"`
	LaunchedAt   int64        `json:"launched_at"`
	CompletedAt  int64        `json:"completed_at"`
	ActorID      int64        `json:"actor_id"`
	UpdatedAt    int64        `json:"_ts,omitempty"`
	ETag         *azcore.ETag `json:"_etag,omitempty"`
}

// JobSummary returns a [JobSummary] for the job.
func (j *Job) JobSummary() *JobSummary {
	return &JobSummary{
		ID:           j.ID,
		RepoID:       j.RepoID,
		OwnerID:      j.OwnerID,
		AssignmentID: j.AssignmentID,
		ComputeID:    j.ComputeID,
		SessionID:    j.SessionID,
		Status:       j.Status,
		CreatedAt:    j.CreatedAt,
		QueuedAt:     j.QueuedAt,
		LaunchedAt:   j.LaunchedAt,
		CompletedAt:  j.CompletedAt,
		ActorID:      j.ActorID,
		UpdatedAt:    j.UpdatedAt,
		ETag:         j.ETag,
	}
}

// JobSummaryFields is the list of fields to select when querying for job
// when only a [JobSummary] is needed.
var JobSummaryFields = []string{
	"id",
	"repo_id",
	"owner_id",
	"assignment_id",
	"compute_id",
	"session_id",
	"status",
	"created_at",
	"queued_at",
	"launched_at",
	"completed_at",
	"actor_id",
	"_ts",
	"_etag",
}

// NewCommand creates a new pending [command.Command] for the job summary.
func (js *JobSummary) NewCommand(externalID string, actorID int64, content string, cmdType command.Type, timestamp int64) *command.Command {
	return &command.Command{
		ID:                command.NewID(),
		JobID:             js.ID,
		AssignmentID:      js.AssignmentID,
		RepoID:            js.RepoID,
		OwnerID:           js.OwnerID,
		SessionID:         js.SessionID,
		ExternalID:        externalID,
		ActorID:           actorID,
		Content:           content,
		Status:            command.StatusPending,
		Type:              cmdType,
		ExternalTimestamp: timestamp,
	}
}
