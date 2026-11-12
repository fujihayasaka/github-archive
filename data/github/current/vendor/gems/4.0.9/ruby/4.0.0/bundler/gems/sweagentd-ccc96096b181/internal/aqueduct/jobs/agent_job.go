package jobs

import (
	"context"

	"github.com/github/go-http/middleware/requestid"
	"github.com/github/sweagentd/internal/goerrors"
	db "github.com/github/sweagentd/internal/jobs"
	"google.golang.org/protobuf/proto"
)

// AgentJobQueueName is the name of the queue for agent jobs.
const AgentJobQueueName = "agent-job-queue"

// AgentJobMaxRequeueCount is the maximum number of times an agent job can be requeued.
// TODO (colbylwilliams): make configurable?
// AgentJobMaxRequeueCount should be set such that the max total time a job can
// spend in the queued state divided by [limiter.JobRequeueDelay]
//
// **TOTAL TIME SHOULD BE 60 MINUTES**
//
// - limiter.JobRequeueDelay (90 seconds) * AgentJobMaxRequeueCount
const AgentJobMaxRequeueCount = 40 // check the value of limiter.JobRequeueDelay before changing

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
		return goerrors.Errorf("failed to unmarshal %T: %w", j, unmarshalErr)
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
		AgentId:           job.AgentID,
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

// GetAgentID returns the agent ID.
func (j *AgentJob) GetAgentID() int64 {
	return j.GetAgentId()
}
