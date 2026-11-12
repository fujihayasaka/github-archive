package jobs

import (
	"context"
	"fmt"

	"github.com/github/go-http/middleware/requestid"
	db "github.com/github/sweagentd/internal/jobs"
	"google.golang.org/protobuf/proto"
)

// APIJobQueueName is the name of the queue for agent jobs.
const APIJobQueueName = "api-job-queue"

// APIJobMaxRequeueCount is the maximum number of times an api job can be requeued.
// TODO (colbylwilliams): make configurable?
const APIJobMaxRequeueCount = 5

// QueueName returns the queue name for api jobs.
func (j *APIJob) QueueName() string { return APIJobQueueName }

// MaxRequeueCount returns the maximum number of times this job can be requeued.
func (j *APIJob) MaxRequeueCount() int32 { return APIJobMaxRequeueCount }

// Marshal serializes the api job to bytes.
func (j *APIJob) Marshal() ([]byte, error) {
	data, err := proto.Marshal(j)
	return data, err
}

// Unmarshal deserializes bytes into the api job.
func (j *APIJob) Unmarshal(data []byte) error {
	unmarshalErr := (proto.UnmarshalOptions{
		DiscardUnknown: true,
	}).Unmarshal(data, j)
	if unmarshalErr != nil {
		return fmt.Errorf("failed to unmarshal %T: %w", j, unmarshalErr)
	}
	return nil
}

// SetRequeueCount sets the number of times this job has been requeued.
func (j *APIJob) SetRequeueCount(count int32) {
	j.RequeueCount = count
}

// ToAPIJob converts a db.Job to an APIJob for queuing in the aqueduct job queue.
func ToAPIJob(ctx context.Context, job *db.Job) *APIJob {
	return &APIJob{
		AssignmentId:    job.AssignmentID,
		JobId:           job.ID,
		OwnerId:         job.OwnerID,
		RepositoryId:    job.RepoID,
		ActorId:         job.ActorID,
		SessionId:       job.SessionID,
		GithubRequestId: requestid.GetGitHubRequestID(ctx),
	}
}

// GetRepositoryID returns the repository ID for the job.
// This implements part of the sweagentd.Repository interface.
func (j *APIJob) GetRepositoryID() int64 {
	return j.RepositoryId
}

// GetOwnerID returns the owner ID for the job.
// This implements part of the sweagentd.Repository interface.
func (j *APIJob) GetOwnerID() int64 {
	return j.OwnerId
}
