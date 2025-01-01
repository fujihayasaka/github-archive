/*
Package tracking defines common workflows to track protobuf messages into our analytics systems
It sets the main steps to track a message, but the concrete actions to cleanup data and filtering
are defined by consumers of this package.
*/
package tracking

import (
	"context"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"google.golang.org/protobuf/proto"

	"github.com/github/notifyd/internal/pkg/job"
	"github.com/github/notifyd/internal/pkg/tenancy"
)

// Publisher represents a tracking publisher
type Publisher interface {
	Publish(ctx context.Context, msg proto.Message) error
}

/*
Ref helps us to narrow down two things:
  - We want to use something that implements the proto.Message interface
  - We want to make sure it is a reference

Thanks to those two properties we can initialize instances of generic types
as pointers

Example:

	// This function uses a reference to the type schemas.MyMessage
	func doit(msg *schemas.MyMessage) {
		// do something
	}

	func perform[T any, R Ref[T]](fn func(msg R)) {
		// here new(T) creates a pointer to T,
		// and then we cast it into R, ensuring the constraints are met
		msg := R(new(T))
		// do things
		fn(msg)
		// do more things
	}

	func main() {
		// Here: T == schemas.MyMessage and R == *schemas.MyMessage
		perform(doit) // No need to declare types as they are inferred from `doit`
	}
*/
type Ref[T any] interface {
	proto.Message
	*T
}

// Filter is a function that determines if a message should be tracked
type Filter[M proto.Message] func(msg M) (bool, string)

// Scrubber is a function that removes or changes data from a message
type Scrubber[M proto.Message] func(msg M) error

/*
JobTracker is a job.Handler that will:
  - Unmarshal protobuf messages from a job.Request
  - Determine if they should be tracked with a Filter
  - Scrub data from them using a collection of Scrubbers
  - Publish the message to the tracking system using a Publisher

JobTracker sets the main flow for tracking a message, and tries to respect context cancelations.
The specific steps to filter and scrub data are injected by consumers of this struct.
*/
type JobTracker[T any, R Ref[T]] struct {
	label     string
	publisher Publisher
	filter    Filter[R]     // Filter works on the reference
	scrubbers []Scrubber[R] // Scrubbers work on the reference since they mutate data
}

// NewJobTracker creates a new JobTracker
func NewJobTracker[T any, R Ref[T]](label string, publisher Publisher, filter Filter[R], scrubbers ...Scrubber[R]) JobTracker[T, R] {
	return JobTracker[T, R]{
		label:     label,
		publisher: publisher,
		filter:    filter,
		scrubbers: scrubbers,
	}
}

// Run implements the job.Handler interface
func (t JobTracker[T, R]) Run(ctx context.Context, tenant tenancy.Tenant, logger log.Logger, req job.Request) error {
	logger = logger.WithContext(ctx).WithFields(kvp.String("gh.notifyd.ctx", t.label))

	msg := R(new(T))
	if err := req.UnmarshalMessage(msg); err != nil {
		logger.WithError(err).Info("error unmarshalling message")
		return err
	}

	if isDone(ctx) {
		return ctx.Err()
	}

	if ok, reason := t.filter(msg); !ok {
		logger.Info("skipping message", kvp.String("gh.notifyd.tracking.skip_reason", reason))
		return nil
	}

	for _, scrub := range t.scrubbers {
		if err := scrub(msg); err != nil {
			logger.WithError(err).Info("error scrubbing data from message")
			return err
		}

		if isDone(ctx) {
			return ctx.Err()
		}
	}

	if err := t.publisher.Publish(ctx, msg); err != nil {
		logger.WithError(err).Info("error publishing tracking message")
		return err
	}

	return nil
}

func isDone(ctx context.Context) bool {
	select {
	case <-ctx.Done():
		return true
	default:
		return false
	}
}
