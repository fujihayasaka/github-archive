package hydro

import (
	"context"

	"github.com/github/hydro-client-go/v7/pkg/hydro"
	"google.golang.org/protobuf/proto"

	metricspkg "github.com/github/notifyd/internal/pkg/job/metrics"
)

// MeteredPublisher sends the protobuf message to Hydro and tracks our internal metrics
type MeteredPublisher struct {
	topic      string
	metricName string
	publisher  *hydro.Publisher
	metrics    *metricspkg.PublisherMetrics
}

// NewMeteredPublisher creates a new MeteredPublisher
func NewMeteredPublisher(topic, metricName string, publisher *hydro.Publisher, metrics *metricspkg.PublisherMetrics) MeteredPublisher {
	return MeteredPublisher{
		topic:      topic,
		metricName: metricName,
		publisher:  publisher,
		metrics:    metrics,
	}
}

// Publish publishes the message to Hydro with telemetry
func (p MeteredPublisher) Publish(ctx context.Context, msg proto.Message) error {
	// Our internal hydro.publisher doesn't use context, so we can't propagate cancellation
	// We do it manually
	control := make(chan error, 1)
	go func() {
		defer close(control)

		err := p.publisher.Publish(msg.ProtoReflect().Interface(), hydro.WithTopic(p.topic))
		p.metrics.Send(ctx, p.metricName, err, metricspkg.WithHydroKey())

		if err != nil {
			control <- err
		}
	}()

	select {
	case <-ctx.Done():
		return ctx.Err()
	case maybeErr := <-control:
		return maybeErr
	}
}
