package aqueduct

import (
	"context"
	"strings"
	"time"

	aq "github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
	"github.com/github/dependency-snapshots-api/pkg/proto/jobs"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/pkg/errors"
	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/types/known/timestamppb"
)

// ParseEchoPayload decodes job payload bytes into EchoPayload.
func ParseEchoPayload(payload []byte) (*jobs.EchoJob, error) {
	body := &jobs.EchoJob{}
	if err := proto.Unmarshal(payload, body); err != nil {
		return &jobs.EchoJob{}, errors.Wrap(err, "unmarshal echo payload")
	}
	if strings.TrimSpace(body.GetMessage()) == "" {
		return &jobs.EchoJob{}, errors.New("echo message is empty")
	}
	return body, nil
}

// NewEchoHandler returns a handler that logs receipt of an echo job.
func NewEchoHandler(logger log.Logger) aq.JobHandler {
	return func(ctx context.Context, rr aq.ReceiveResult) error {
		payload, err := ParseEchoPayload(rr.Payload)
		if err != nil {
			return err
		}

		logger.Info(
			"processed aqueduct echo job",
			kvp.String("job_id", rr.ID),
			kvp.String("queue", rr.Queue),
			kvp.String("message", payload.Message),
		)

		return nil
	}
}

// SendEcho builds and enqueues an echo job.
func SendEcho(ctx context.Context, je Enqueuer, message string, now time.Time) (string, error) {
	msg := &jobs.EchoJob{Message: message, SentAt: timestamppb.New(now)}
	return je.Enqueue(ctx, msg)
}
