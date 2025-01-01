// Package consumers contains Hydro consumers for various topics
package consumers

import (
	"context"
	"strings"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	envelope "github.com/github/hydro-client-go/v7/generated/hydro/v1"
	"github.com/github/hydro-client-go/v7/pkg/hydro"
	"github.com/github/turboscan/ts"
	"go.opentelemetry.io/otel/attribute"

	tshydro "github.com/github/hydro-schemas-go/hydro/schemas/code_scanning/v0"
	"github.com/github/turboscan/ts/appctx"
	"github.com/github/turboscan/ts/flipper"
	"github.com/github/turboscan/ts/hydro/topics"
	"github.com/github/turboscan/ts/jobs"
	"github.com/github/turboscan/ts/o11y"
	"github.com/github/turboscan/ts/processor"
	"github.com/github/turboscan/ts/twirp/clients/aqueduct"
	oteltrace "go.opentelemetry.io/otel/trace"

	"github.com/pkg/errors"
)

// AnalysisEventProcessor is responsible for processing and reacting to NewAnalysis messages.
// It implements the HydroProcessor interface.
type AnalysisEventProcessor struct {
	aqueduct        aqueduct.JobPerformer
	deliveryCreator processor.DeliveryCreator

	// Error handling parameters
	maxRetryElapsedTime time.Duration
	retryDelay          time.Duration
}

// Verify that AnalysisEventProcessor implements the HydroProcessor interface
var _ hydroProcessor = (*AnalysisEventProcessor)(nil)

const errorConvertingAnalysisToDelivery = "error converting Analysis message to Delivery"

func NewAnalysisEventProcessor(aqueductClient aqueduct.JobPerformer, deliveryCreator processor.DeliveryCreator, maxRetryElapsedTime time.Duration) *AnalysisEventProcessor {

	return &AnalysisEventProcessor{
		aqueduct:            aqueductClient,
		deliveryCreator:     deliveryCreator,
		maxRetryElapsedTime: maxRetryElapsedTime,
		retryDelay:          1 * time.Second,
	}

}

func (a *AnalysisEventProcessor) ProcessorName() string {
	return "AnalysisEventProcessor"
}

func (a *AnalysisEventProcessor) ProcessEnvelope(ctx context.Context, envelope *envelope.Envelope, topic string) error {

	var msg tshydro.Analysis

	err := UnwrapAnalysisMessage(envelope.Message, &msg)
	if err != nil {
		return errors.Wrap(err, "unmarshalling analysis message")
	}

	return a.NewAnalysis(ctx, &msg)
}

func (a *AnalysisEventProcessor) Topics() []string {
	return []string{topics.NewAnalysis}
}

// NewAnalysis processes a NewAnalysis message.  If a failure occurs
// during processing, this procedure will stop retrying after
// maxRetryElapsedTime has passed
func (a *AnalysisEventProcessor) NewAnalysis(ctx context.Context, m *tshydro.Analysis) error {
	ctx = appctx.WithRequestID(ctx, m.RequestId)
	ctx = appctx.WithRepositoryID(ctx, m.RepositoryId)

	ctx, span := o11y.StartSpan(ctx,
		oteltrace.WithAttributes(attribute.Int("gh.repo.id", int(m.RepositoryId))),
		oteltrace.WithAttributes((attribute.String("gh.request_id", m.RequestId))),
	)
	defer span.End()

	appctx.Logger(ctx).Info("New analysis message received")
	taggedStatsClient(ctx, m).Counter("newanalysis.started", stats.Tags{}, 1)

	delivery, err := DeliveryFromProto(m)
	if err != nil {
		// If the proto message is corrupted there is nothing we can do
		appctx.Logger(ctx).WithError(err).Error(errorConvertingAnalysisToDelivery)
		return errors.Wrap(err, errorConvertingAnalysisToDelivery)
	}

	// once this field is updated then the delivery will become eligible for processing by the
	// ProcessDelivery job.
	// we create deliveries as placeholders in other locations but it is only at this point where can
	// save the record with all the data needed to successfully process the delivery
	startTime := time.Now()
	delivery.ProcessingStartedAt = &startTime

	ctx = flipper.StoreLimitAlertFixesInContext(ctx, delivery.RepositoryID)

	err = a.deliveryCreator.CreateDelivery(ctx, delivery)
	if err != nil {
		return err
	}
	_, err = a.aqueduct.PerformLater(ctx, jobs.ProcessDelivery{RepoID: delivery.RepositoryID})

	if delivery.HydroEnqueuedAt != nil {
		appctx.Stats(ctx).DistributionMs("newanalysis.processing_duration_part", stats.Tags{"stage": "hydro"}, time.Since(*delivery.HydroEnqueuedAt))
	}

	appctx.Logger(ctx).WithFields(kvp.Float64("gh.operation.duration", float64(time.Since(startTime)))).
		WithError(err).
		Info("Analysis message processed")

	if err == nil {
		return nil
	}

	if ctx.Err() != nil {
		return ctx.Err()
	}

	return err
}

// HandleError is part of the hydro consumer lifecycle
// As we have explicit retry logic in the Hydro ConsumerServer, this method usually returns nil.
func (a *AnalysisEventProcessor) HandleError(ctx context.Context, err error, m *hydro.Message) error {
	appctx.Stats(ctx).Counter("newanalysis.status", stats.Tags{"success": "false"}, 1)
	return handleError(ctx, err, m)
}

// Returns a version of the stats client that may include additional
// tags depending on message content
func taggedStatsClient(ctx context.Context, m *tshydro.Analysis) stats.Client {
	if strings.HasPrefix(m.RepoNwo, "dsp-testing/") {
		return appctx.Stats(ctx).WithTags(stats.Tags{"owner": "dsp-testing"})
	}
	return appctx.Stats(ctx)
}

func (a *AnalysisEventProcessor) GetRetryPolicy() RetryPolicy {
	return RetryPolicy{MaxRetryElapsedTime: a.maxRetryElapsedTime, RetryDelay: a.retryDelay}
}

// BeforeRetry is called by the Hydro ConsumerServer and so we need to rebuild the logging context
func (a *AnalysisEventProcessor) BeforeRetry(ctx context.Context, lastErr error, errCnt int, e *envelope.Envelope, m *hydro.Message) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	var msg tshydro.Analysis

	err := UnwrapAnalysisMessage(e.Message, &msg)
	if err != nil {
		// if this in an error unmarshalling then we expect it was thrown in the original call, but we still want to log the retry
		// we also cannot error out in the BeforeRetry callback because the callback shouldn't jeopardise retrying.
		appctx.Logger(ctx).WithError(lastErr).Info("retrying message due to error", kvp.Int("gh.turboscan.errCount", errCnt))
		return
	}

	ctx = appctx.WithRequestID(ctx, msg.RequestId)
	ctx = appctx.WithRepositoryID(ctx, msg.RepositoryId)

	appctx.Logger(ctx).WithError(lastErr).Info("retrying message due to error", kvp.Int("gh.turboscan.errCount", errCnt))
	taggedStatsClient(ctx, &msg).Counter("newanalysis.retried", stats.Tags{}, 1)
}

func (a *AnalysisEventProcessor) OnPermanentFailure(ctx context.Context, e *envelope.Envelope, m *hydro.Message) error {
	var msg tshydro.Analysis

	err := UnwrapAnalysisMessage(e.Message, &msg)
	if err != nil {
		return err
	}

	ctx = appctx.WithRequestID(ctx, msg.RequestId)
	ctx = appctx.WithRepositoryID(ctx, msg.RepositoryId)

	appctx.Logger(ctx).Error("gave up while processing new analysis delivery", ts.RepositoryEID(msg.RepositoryId).AsKVP())
	taggedStatsClient(ctx, &msg).Counter("newanalysis.gave_up", stats.Tags{}, 1)
	return err
}
