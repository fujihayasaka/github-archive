package sweagentd

import (
	"context"
	"time"

	"github.com/github/aqueduct-client-go/v3/pkg/aqueduct"
	"google.golang.org/protobuf/proto"
)

// AqueductJob defines the interface for jobs that can be processed by Aqueduct.
type AqueductJob interface {
	proto.Message

	QueueName() string
	MaxRequeueCount() int32
	Marshal() ([]byte, error)
	Unmarshal(data []byte) error
	GetRequeueCount() int32
	SetRequeueCount(int32)
}

// AqueductClient defines the interface for interacting with the Aqueduct service.
// Preferably we'd name this something more generic like JobQueueClient, but
// we can do that later and for now want to avoid too much of a large rename concern.
type AqueductClient interface {
	AppName() string
	AqueductURL() string

	InternalClient() aqueduct.Client

	// QueueJob queues an (aqueduct) job for later processing.
	QueueJob(ctx context.Context, job AqueductJob) (string, error)

	// ScheduleJob schedules an (aqueduct) job for processing at a specific time.
	// If deliverAt is zero, it defaults to immediate processing.
	ScheduleJob(ctx context.Context, job AqueductJob, deliverAt time.Time) (string, error)

	// RequeueJob requeues an (aqueduct) job for later processing using the
	// default redelivery delay. This is the same as calling RequeueJobWithDelay
	// with a negative delay.
	RequeueJob(ctx context.Context, job AqueductJob) (string, error)

	// RequeueJobWithDelay requeues an (aqueduct) job for later processing with
	// an optional delay. If delay is negative, the client's configured default
	// redelivery delay is used. If delay is zero, no delay is applied.
	RequeueJobWithDelay(ctx context.Context, job AqueductJob, delay time.Duration) (string, error)

	// QueueDepth returns the current depth (number of pending jobs) for the
	// named queue under this client's app. Used by scheduling hooks to throttle
	// dequeue rate or widen jitter under load. Implementations may cache the
	// reading per queue for a short TTL to bound Aqueduct load when called
	// from a hot tick loop.
	QueueDepth(ctx context.Context, queue string) (int64, error)
}
