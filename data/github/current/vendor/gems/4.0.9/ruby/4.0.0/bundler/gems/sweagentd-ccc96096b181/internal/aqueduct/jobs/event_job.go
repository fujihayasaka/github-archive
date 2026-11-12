package jobs

import (
	"context"

	"github.com/github/go-http/middleware/requestid"
	"github.com/github/sweagentd/internal/events/hydro/topics"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/sweagentd"
	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/types/known/timestamppb"
)

const (
	// EventJobQueueName is the name of the queue for event jobs.
	EventJobQueueName = "event-job-queue"

	// EventJobTriggerQueueName is the name of the trigger queue for event jobs.
	EventJobTriggerQueueName = "event-job-trigger-queue"

	// EventJobBackgroundQueueName is the name of the background (lower priority) queue for event jobs.
	EventJobBackgroundQueueName = "event-job-background-queue"
)

// EventJobServiceQueues are the eventJob queues the sweagentd service that the
// aqueduct consumer should listen to and handle.
//
// IMPORTANT: Queues should only be included in Service OR Worker, not both.
// New queues should be added to Worker. Queues currently in Service will be
// gradually migrated to Worker over time.
//
// ORDER MATTERS: Queues listed earlier have higher priority.
var EventJobServiceQueues = []string{
	EventJobQueueName,
	EventJobBackgroundQueueName,
}

// EventJobWorkerQueues are the eventJob queues the sweagentd worker that the
// aqueduct consumer should listen to and handle.
//
// IMPORTANT: Queues should only be included in Service OR Worker, not both.
// New queues should be added to Worker. Queues currently in Service will be
// gradually migrated to Worker over time.
//
// ORDER MATTERS: Queues listed earlier have higher priority.
var EventJobWorkerQueues = []string{
	EventJobTriggerQueueName,
}

// EventJobMaxRequeueCount is the maximum number of times an event job can be requeued.
// TODO (colbylwilliams): make configurable?
const EventJobMaxRequeueCount = 5

// QueueName returns the queue name for event jobs.
func (j *EventJob) QueueName() string {
	switch j.Topic {
	case
		topics.PullRequestClose,
		topics.PullRequestMerge,
		topics.PullRequestReopen:
		return EventJobBackgroundQueueName
	case topics.IssueCreateTemplate:
		return EventJobTriggerQueueName
	default:
		return EventJobQueueName
	}
}

// MaxRequeueCount returns the maximum number of times this job can be requeued.
func (j *EventJob) MaxRequeueCount() int32 { return EventJobMaxRequeueCount }

// Marshal serializes the event job to bytes.
func (j *EventJob) Marshal() ([]byte, error) {
	data, err := proto.Marshal(j)
	return data, err
}

// Unmarshal deserializes bytes into the event job.
func (j *EventJob) Unmarshal(data []byte) error {
	unmarshalErr := (proto.UnmarshalOptions{
		DiscardUnknown: true,
	}).Unmarshal(data, j)
	if unmarshalErr != nil {
		return goerrors.Errorf("failed to unmarshal %T: %w", j, unmarshalErr)
	}
	return nil
}

// SetRequeueCount sets the number of times this job has been requeued.
func (j *EventJob) SetRequeueCount(count int32) {
	j.RequeueCount = count
}

type envelope interface {
	GetId() string
	GetMessage() []byte
	GetTimestamp() *timestamppb.Timestamp
}

// ToEventJob creates an EventJob from event components.
func ToEventJob(ctx context.Context, topic string, envelope envelope, message proto.Message, event sweagentd.Event) *EventJob {
	return &EventJob{
		Id:              envelope.GetId(),
		Topic:           topic,
		Message:         envelope.GetMessage(),
		Timestamp:       envelope.GetTimestamp(),
		OwnerId:         event.GetOwnerID(),
		RepositoryId:    event.GetRepositoryID(),
		ActorId:         event.GetActorID(),
		GithubRequestId: requestid.GetGitHubRequestID(ctx),
		AgentId:         event.GetAgentID(),
	}
}

// GetAgentID returns the agent ID.
func (j *EventJob) GetAgentID() int64 {
	return j.AgentId
}
