// Package jobevents contains helpers for emitting job-related Hydro events.
package jobevents

import (
	"time"

	"github.com/github/hydro-client-go/v7/pkg/hydro"
	sweagentdv1 "github.com/github/hydro-schemas-go/hydro/schemas/sweagentd/v1"
	"github.com/github/hydro-schemas-go/hydro/schemas/sweagentd/v1/entities"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/google/uuid"
	"google.golang.org/protobuf/types/known/timestamppb"
)

// SessionsLegacyNamespace is the namespace used for progress updates from the
// legacy sessions callback endpoint.
const SessionsLegacyNamespace = "sessions-legacy"

// ProgressUpdate contains the data needed to emit a progress entity.
type ProgressUpdate struct {
	// Content is the raw JSON content of the progress update.
	Content []byte
	// Namespace categorizes the progress update (e.g., "sessions-legacy").
	Namespace string
	// Kind indicates the type of progress update (e.g., "log").
	Kind string
	// Version is the version of the progress update schema.
	Version string
	// CreatedAt is the time the progress update was created.
	CreatedAt time.Time
}

// EmitJobUpdated emits a JobUpdated event to the given Hydro publisher.
// The event is partitioned by job ID to ensure ordering.
func EmitJobUpdated(publisher *hydro.Publisher, job *jobs.Job) error {
	return publisher.Publish(&sweagentdv1.JobUpdated{
		Job: mapJob(job),
	}, hydro.WithPartitionKey(job.ID))
}

// EmitJobProgress emits a JobProgress event to the given Hydro publisher.
// The event is partitioned by job ID to ensure ordering.
func EmitJobProgress(publisher *hydro.Publisher, job *jobs.Job, progress *ProgressUpdate) error {
	return publisher.Publish(&sweagentdv1.JobProgress{
		Job:      mapJob(job),
		Progress: mapProgress(progress),
	}, hydro.WithPartitionKey(job.ID))
}

func mapJob(job *jobs.Job) *entities.Job {
	entityJob := &entities.Job{
		Id:           job.ID,
		AssignmentId: job.AssignmentID,
		AgentId:      job.AgentID,
		Actor:        mapActor(job),
		Status:       mapJobStatus(job.Status),
		Repository:   mapRepository(job),
		CustomAgent:  mapCustomAgent(job),
		Event:        mapEvent(job),
		CreatedAt:    timestampFromUnix(job.CreatedAt),
		QueuedAt:     timestampFromUnix(job.QueuedAt),
		StartedAt:    timestampFromUnix(job.LaunchedAt),
		CompletedAt:  timestampFromUnix(job.CompletedAt),
		SessionId:    job.SessionID,
		Title:        job.Title,
		ComputeId:    job.ComputeID,
		Model:        job.Model,
		HeadRef:      job.BranchName,
		BaseRef:      job.BaseCommit,
	}

	// Error is optional
	if job.Error != nil {
		entityJob.Error = mapJobError(job.Error)
	}

	// PullRequest is optional
	if job.HasPullRequest() {
		entityJob.PullRequest = mapPullRequest(job)
	}

	return entityJob
}

func mapActor(job *jobs.Job) *entities.Actor {
	return &entities.Actor{
		Id:                  job.ActorID,
		Login:               job.ActorLogin,
		DisplayLogin:        job.ActorDisplayLogin,
		AnalyticsTrackingId: job.ActorAnalyticsTrackingID,
	}
}

func mapJobStatus(status jobs.JobStatus) entities.JobStatus {
	switch status {
	case jobs.JobStatusPending:
		return entities.JobStatus_PENDING
	case jobs.JobStatusQueued:
		return entities.JobStatus_QUEUED
	case jobs.JobStatusRunning:
		return entities.JobStatus_RUNNING
	case jobs.JobStatusCompleted:
		return entities.JobStatus_COMPLETED
	case jobs.JobStatusFailed:
		return entities.JobStatus_FAILED
	case jobs.JobStatusCancelled:
		return entities.JobStatus_CANCELLED
	case jobs.JobStatusTimedOut:
		return entities.JobStatus_TIMED_OUT
	default:
		return entities.JobStatus_UNKNOWN
	}
}

func mapRepository(job *jobs.Job) *entities.Repository {
	return &entities.Repository{
		Id:          job.RepoID,
		NodeId:      job.RepoNodeID,
		OwnerId:     job.OwnerID,
		OwnerNodeId: job.OwnerNodeID,
	}
}

func mapCustomAgent(job *jobs.Job) *entities.CustomAgent {
	if !job.HasCustomAgent() {
		return nil
	}

	return &entities.CustomAgent{
		Name:        job.CustomAgent.Name,
		Version:     job.CustomAgent.Version,
		Repository:  mapCustomAgentRepository(job),
		DisplayName: job.CustomAgent.DisplayName,
		Description: job.CustomAgent.Description,
	}
}

func mapCustomAgentRepository(job *jobs.Job) *entities.Repository {
	return &entities.Repository{
		Id:      job.CustomAgent.RepoID,
		OwnerId: job.CustomAgent.RepoOwnerID,
		// Note: NodeId and OwnerNodeId are not available in CustomAgent DBRecord
	}
}

func mapEvent(job *jobs.Job) *entities.Event {
	return &entities.Event{
		Type:        string(job.EventType),
		Url:         job.EventURL,
		Identifiers: job.EventIdentifiers,
		Content:     job.EventContent,
	}
}

func mapJobError(jobError *jobs.JobError) *entities.JobError {
	return &entities.JobError{
		Code:    jobError.ResponseStatusCode,
		Message: jobError.Message,
	}
}

func mapPullRequest(job *jobs.Job) *entities.PullRequest {
	return &entities.PullRequest{
		Id:     job.PullRequestID,
		Number: int32(job.PullRequestNumber),
	}
}

func timestampFromUnix(seconds int64) *timestamppb.Timestamp {
	if seconds == 0 {
		return nil
	}
	return timestamppb.New(time.Unix(seconds, 0))
}

func mapProgress(progress *ProgressUpdate) *entities.Progress {
	if progress == nil {
		return nil
	}

	return &entities.Progress{
		Id:        uuid.NewString(),
		Namespace: progress.Namespace,
		Kind:      progress.Kind,
		Version:   progress.Version,
		Content:   progress.Content,
		CreatedAt: timestamppb.New(progress.CreatedAt),
	}
}
