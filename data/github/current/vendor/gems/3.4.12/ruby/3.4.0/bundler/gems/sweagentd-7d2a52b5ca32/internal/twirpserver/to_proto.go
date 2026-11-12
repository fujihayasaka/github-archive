package twirpserver

import (
	"time"

	"github.com/github/sweagentd/internal/jobs"
	proto "github.com/github/sweagentd/proto/jobs/v1"
	"google.golang.org/protobuf/types/known/timestamppb"
)

func jobToProto(job *jobs.Job) *proto.Job {
	if job == nil {
		return nil
	}

	protoJob := &proto.Job{
		Id:               job.ID,
		RepoId:           job.RepoID,
		OwnerId:          job.OwnerID,
		RepoNodeId:       job.RepoNodeID,
		OwnerNodeId:      job.OwnerNodeID,
		AssignmentId:     job.AssignmentID,
		PullRequestId:    job.PullRequestID,
		ComputeId:        job.ComputeID,
		SessionId:        job.SessionID,
		EventType:        convertEventType(job.EventType),
		EventUrl:         job.EventURL,
		EventIdentifiers: job.EventIdentifiers,
		EventContent:     job.EventContent,
		Status:           convertJobStatus(job.Status),
		Model:            job.Model,
		BranchName:       job.BranchName,
		BaseCommit:       job.BaseCommit,
		ActorId:          job.ActorID,
	}

	// Convert timestamps
	if job.CreatedAt != 0 {
		protoJob.CreatedAt = timestamppb.New(time.Unix(job.CreatedAt, 0))
	}
	if job.LaunchedAt != 0 {
		protoJob.LaunchedAt = timestamppb.New(time.Unix(job.LaunchedAt, 0))
	}
	if job.QueuedAt != 0 {
		protoJob.QueuedAt = timestamppb.New(time.Unix(job.QueuedAt, 0))
	}
	if job.CompletedAt != 0 {
		protoJob.CompletedAt = timestamppb.New(time.Unix(job.CompletedAt, 0))
	}
	if job.UpdatedAt != 0 {
		protoJob.UpdatedAt = timestamppb.New(time.Unix(job.UpdatedAt, 0))
	}

	return protoJob
}

func convertJobStatus(status jobs.JobStatus) proto.JobStatus {
	switch status {
	case jobs.JobStatusPending:
		return proto.JobStatus_JOB_STATUS_PENDING
	case jobs.JobStatusQueued:
		return proto.JobStatus_JOB_STATUS_QUEUED
	case jobs.JobStatusRunning:
		return proto.JobStatus_JOB_STATUS_RUNNING
	case jobs.JobStatusCompleted:
		return proto.JobStatus_JOB_STATUS_COMPLETED
	case jobs.JobStatusFailed:
		return proto.JobStatus_JOB_STATUS_FAILED
	case jobs.JobStatusCancelled:
		return proto.JobStatus_JOB_STATUS_CANCELLED
	case jobs.JobStatusTimedOut:
		return proto.JobStatus_JOB_STATUS_TIMED_OUT
	default:
		return proto.JobStatus_JOB_STATUS_INVALID
	}
}

func convertEventType(eventType jobs.EventType) proto.EventType {
	switch eventType {
	case jobs.EventTypeIssueAssignment:
		return proto.EventType_EVENT_TYPE_ISSUE_ASSIGNMENT
	case jobs.EventTypePullRequestComment:
		return proto.EventType_EVENT_TYPE_PULL_REQUEST_COMMENT
	case jobs.EventTypePullRequestReview:
		return proto.EventType_EVENT_TYPE_PULL_REQUEST_REVIEW
	case jobs.EventTypeCodeScanningAlertsAssignment:
		return proto.EventType_EVENT_TYPE_CODE_SCANNING_ALERTS_ASSIGNMENT
	case jobs.EventTypeApiCallReceived:
		return proto.EventType_EVENT_TYPE_API_CALL_RECEIVED
	default:
		return proto.EventType_EVENT_TYPE_INVALID
	}
}
