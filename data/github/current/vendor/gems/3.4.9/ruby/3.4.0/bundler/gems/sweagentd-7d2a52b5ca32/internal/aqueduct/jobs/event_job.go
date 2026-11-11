package jobs

import (
	"context"
	"fmt"

	"github.com/github/go-http/middleware/requestid"
	"github.com/github/sweagentd/internal/events/hydro/topics"
	"github.com/github/sweagentd/internal/sweagentd"
	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/types/known/timestamppb"
)

// EventJobQueueName is the name of the queue for event jobs.
const EventJobQueueName = "event-job-queue"

// EventJobBackgroundQueueName is the name of the background (lower priority) queue for event jobs.
const EventJobBackgroundQueueName = "event-job-background-queue"

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
		return fmt.Errorf("failed to unmarshal %T: %w", j, unmarshalErr)
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
func ToEventJob(ctx context.Context, topic string, envelope envelope, message proto.Message, event sweagentd.RepositoryWithActor) *EventJob {
	return &EventJob{
		Id:              envelope.GetId(),
		Topic:           topic,
		Message:         envelope.GetMessage(),
		Timestamp:       envelope.GetTimestamp(),
		OwnerId:         event.GetOwnerID(),
		RepositoryId:    event.GetRepositoryID(),
		ActorId:         event.GetActorID(),
		GithubRequestId: requestid.GetGitHubRequestID(ctx),
	}
}
