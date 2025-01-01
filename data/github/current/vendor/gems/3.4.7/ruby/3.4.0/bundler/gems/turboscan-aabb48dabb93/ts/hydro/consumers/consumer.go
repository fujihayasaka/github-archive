package consumers

import (
	"context"
	"time"

	"github.com/IBM/sarama"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-http/v2/middleware/headers"
	"github.com/github/go-http/v2/middleware/tenant"
	"github.com/pkg/errors"

	envelope "github.com/github/hydro-client-go/v7/generated/hydro/v1"
	"github.com/github/hydro-client-go/v7/pkg/hydro"
	"github.com/github/turboscan/ts/appctx"
	"github.com/github/turboscan/ts/flipper"
)

// hydroProcessor is the interface that must be implemented by each event consumer
type hydroProcessor interface {
	HandleError(context.Context, error, *hydro.Message) error
	ProcessEnvelope(context.Context, *envelope.Envelope, string) error
	GetRetryPolicy() RetryPolicy
	Topics() []string
	BeforeRetry(context.Context, error, int, *envelope.Envelope, *hydro.Message)
	OnPermanentFailure(context.Context, *envelope.Envelope, *hydro.Message) error
	ProcessorName() string
}

type RetryPolicy struct {
	MaxRetryElapsedTime time.Duration
	RetryDelay          time.Duration
}

// ConsumerServer represents a long-running consumer loop for a specific HydroProcessor
type ConsumerServer struct {
	logger log.Logger
	source hydro.Source

	processor hydroProcessor
}

var ConsumeFromNewestOffset = hydro.WithSaramaConfig(
	func(c *sarama.Config) {
		c.Consumer.Offsets.Initial = sarama.OffsetNewest
	},
)

func NewConsumerServer(kc hydro.KafkaConfig, group string, h hydroProcessor, logger log.Logger, opts ...hydro.KafkaConfigOption) (*ConsumerServer, error) {
	for _, opt := range opts {
		if err := opt(&kc); err != nil {
			return nil, err
		}
	}
	// Wait for the processor to be unpaused before registering with Kafka
	for h != nil && flipper.HasProcessorDisabled(context.Background(), h.ProcessorName()) {
		logger.Info("processor is paused, waiting for it to be unpaused", kvp.String("gh.processor.name", h.ProcessorName()))
		<-time.After(10 * time.Second)
	}

	src, err := hydro.NewKafkaSource(kc, group, h.Topics())
	if err != nil {
		return nil, errors.Wrap(err, "creating kafka source")
	}

	return &ConsumerServer{
		source:    src,
		processor: h,
		logger:    logger,
	}, nil
}

// Start starts consuming messages from the configured source and passes them to the processor.
// It returns with an error when the context is canceled or it encounters an unrecoverable error.
func (c *ConsumerServer) Start(cx context.Context) error {
	cx, cancel := context.WithCancel(cx)
	go func() {
		for {
			if c.processor != nil && flipper.HasProcessorDisabled(cx, c.processor.ProcessorName()) {
				c.logger.Info("running processor is paused, cancelling context so it'll be restarted", kvp.String("gh.processor.name", c.processor.ProcessorName()))
				cancel()
				return
			}
			<-time.After(10 * time.Second)
		}
	}()

	return c.source.Consume(cx, func(ctx context.Context, m hydro.Message) error {
		ctx = appctx.WithHydroMessage(ctx, m.Topic, m.Partition, m.Offset)
		h := c.processor
		if h == nil {
			e := errors.Errorf("received message for unexpected topic %q", m.Topic)

			c.logger.WithError(e).Error("error when consuming hydro message",
				kvp.String("gh.hydro.msg.topic", m.Topic), kvp.Int("gh.hydro.msg.partition", int(m.Partition)), kvp.Int("gh.hydro.msg.offset", int(m.Offset)))

			return nil
		}
		err := consumeMessage(ctx, h, m)
		if err != nil {
			err = h.HandleError(ctx, err, &m)
		}
		return err
	})
}

func consumeMessage(ctx context.Context, h hydroProcessor, m hydro.Message) (err error) {
	defer func() {
		if p := recover(); p != nil {
			err = errFromPanic(p)
		}
	}()

	// Multi-Tenancy in Proxima requires using a "X-GitHub-Tenant" or "X-GitHub-Tenant-ID" request header across services
	if v := m.Headers[headers.Tenant]; v != "" {
		ctx = tenant.TenantContext(ctx, v)
	}
	if v := m.Headers[headers.TenantID]; v != "" {
		ctx = tenant.TenantIDContext(ctx, v)
	}

	var e envelope.Envelope
	if err := UnwrapEnvelope(m.Value, &e); err != nil {
		return errors.Wrap(err, "unmarshalling hydro envelope")
	}

	retryPolicy := h.GetRetryPolicy()
	startTime := time.Now()
	var lastErr error
	// Always allow a first run with errCnt == 0 for cases where retryPolicy.MaxRetryElapsedTime is zero
	for errCnt := 0; time.Since(startTime) < retryPolicy.MaxRetryElapsedTime || errCnt == 0; errCnt++ {
		// TODO: Check Circuit breaker
		lastErr = consumeMessageInnerLoop(ctx, h, &e, m.Topic, errCnt)
		if lastErr == nil {
			return nil
		}

		if ctx.Err() != nil {
			return ctx.Err()
		}

		h.BeforeRetry(ctx, lastErr, errCnt, &e, &m)

		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-time.After(retryPolicy.RetryDelay):
		}
	}

	err = h.OnPermanentFailure(ctx, &e, &m)
	if err != nil {
		return errors.Wrap(err, "permanent failure handler")
	}
	return lastErr
}

func consumeMessageInnerLoop(ctx context.Context, h hydroProcessor, e *envelope.Envelope, topic string, errCnt int) (err error) {
	defer func() {
		if p := recover(); p != nil {
			err = errFromPanic(p)
		}
	}()
	return h.ProcessEnvelope(ctx, e, topic)
}

func (c *ConsumerServer) Stop(_ context.Context) error {
	return c.source.Close()
}

func errFromPanic(p interface{}) error {
	if err, ok := p.(error); ok {
		// We very rarely use panic in turboscan, and where we do it is
		// with string arguments. Any errors returned by recover() are
		// therefore usually from the Go standard library (e.g. nil
		// pointer dereferences), so we need to attach a stack trace.
		return errors.Wrap(err, "hydro consumer panic handling message")
	}
	return errors.Errorf("hydro consumer panic handling message: %v", p)
}
