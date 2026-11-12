package jobs

import (
	"context"
	"fmt"

	"github.com/github/go-http/middleware/requestid"
	db "github.com/github/sweagentd/internal/jobs"
	"google.golang.org/protobuf/proto"
)

// AgentJobQueueName is the name of the queue for agent jobs.
const AgentJobQueueName = "agent-job-queue"

// AgentJobMaxRequeueCount is the maximum number of times an agent job can be requeued.
// TODO (colbylwilliams): make configurable?
// AgentJobMaxRequeueCount should be set such that the max total time a job can
// in the queued state divided by [limiter.JobRequeueDelay]
//
// Example:
//
//	limiter.JobRequeueDelay = 2 * time.Minute
//	AgentJobMaxRequeueCount = 30
//	// max total queued time = 30 * 2 minutes = 60 minutes
const AgentJobMaxRequeueCount = 30

// QueueName returns the queue name for agent jobs.
func (j *AgentJob) QueueName() string { return AgentJobQueueName }

// MaxRequeueCount returns the maximum number of times this job can be requeued.
func (j *AgentJob) MaxRequeueCount() int32 { return AgentJobMaxRequeueCount }

// Marshal serializes the agent job to bytes.
func (j *AgentJob) Marshal() ([]byte, error) {
	data, err := proto.Marshal(j)
	return data, err
}

// Unmarshal deserializes bytes into the agent job.
func (j *AgentJob) Unmarshal(data []byte) error {
	unmarshalErr := (proto.UnmarshalOptions{
		DiscardUnknown: true,
	}).Unmarshal(data, j)
	if unmarshalErr != nil {
		return fmt.Errorf("failed to unmarshal %T: %w", j, unmarshalErr)
	}
	return nil
}

// SetRequeueCount sets the number of times this job has been requeued.
func (j *AgentJob) SetRequeueCount(count int32) {
	j.RequeueCount = count
}

// ToAgentJob creates an AgentJob from a database job record.
func ToAgentJob(ctx context.Context, job *db.Job) *AgentJob {
	return &AgentJob{
		AssignmentId:      job.AssignmentID,
		JobId:             job.ID,
		OwnerId:           job.OwnerID,
		RepositoryId:      job.RepoID,
		ActorId:           job.ActorID,
		PullRequestId:     job.PullRequestID,
		PullRequestNumber: int32(job.PullRequestNumber),
		SessionId:         job.SessionID,
		GithubRequestId:   requestid.GetGitHubRequestID(ctx),
	}
}

// GetRepositoryID returns the repository ID.
func (j *AgentJob) GetRepositoryID() int64 {
	return j.GetRepositoryId()
}

// GetOwnerID returns the owner ID.
func (j *AgentJob) GetOwnerID() int64 {
	return j.GetOwnerId()
}

// GetActorID returns the actor ID.
func (j *AgentJob) GetActorID() int64 {
	return j.GetActorId()
}
