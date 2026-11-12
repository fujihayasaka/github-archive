package jobs

import (
	"context"

	"github.com/github/go-http/middleware/requestid"
	"github.com/github/sweagentd/internal/goerrors"
	"google.golang.org/protobuf/proto"
)

// StopAgentComputeJobQueueName is the name of the queue for delayed
// stop-agent-compute jobs.
const StopAgentComputeJobQueueName = "stop-agent-compute-job-queue"

// StopAgentComputeJobMaxRequeueCount is the maximum number of times a
// stop-agent-compute job can be requeued.
const StopAgentComputeJobMaxRequeueCount = 5

// QueueName returns the queue name for stop-agent-compute jobs.
func (j *StopAgentComputeJob) QueueName() string { return StopAgentComputeJobQueueName }

// MaxRequeueCount returns the maximum number of times this job can be requeued.
func (j *StopAgentComputeJob) MaxRequeueCount() int32 { return StopAgentComputeJobMaxRequeueCount }

// Marshal serializes the stop-agent-compute job to bytes.
func (j *StopAgentComputeJob) Marshal() ([]byte, error) {
	data, err := proto.Marshal(j)
	return data, err
}

// Unmarshal deserializes bytes into the stop-agent-compute job.
func (j *StopAgentComputeJob) Unmarshal(data []byte) error {
	unmarshalErr := (proto.UnmarshalOptions{
		DiscardUnknown: true,
	}).Unmarshal(data, j)
	if unmarshalErr != nil {
		return goerrors.Errorf("failed to unmarshal %T: %w", j, unmarshalErr)
	}
	return nil
}

// SetRequeueCount sets the number of times this job has been requeued.
func (j *StopAgentComputeJob) SetRequeueCount(count int32) {
	j.RequeueCount = count
}

// NewStopAgentComputeJob constructs a StopAgentComputeJob, propagating the
// current GitHub request ID from the context. The generation argument is the
// value returned by [stopguard.Guard.Record] for this compute ID and is used
// by the handler to detect superseded (i.e. effectively cancelled) jobs.
func NewStopAgentComputeJob(ctx context.Context, computeID string, actorID, generation int64) *StopAgentComputeJob {
	return &StopAgentComputeJob{
		ComputeId:       computeID,
		ActorId:         actorID,
		GithubRequestId: requestid.GetGitHubRequestID(ctx),
		Generation:      generation,
	}
}
