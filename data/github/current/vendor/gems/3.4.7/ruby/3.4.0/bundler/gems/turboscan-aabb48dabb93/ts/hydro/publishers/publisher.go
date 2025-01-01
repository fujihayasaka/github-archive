package publishers

import (
	"context"

	"github.com/github/go-stats"

	"github.com/github/hydro-client-go/v7/pkg/hydro"
	auditLogHydro "github.com/github/hydro-schemas-go/hydro/schemas/audit_log/v2"
	tshydro "github.com/github/hydro-schemas-go/hydro/schemas/code_scanning/v0"
	insightshydro "github.com/github/hydro-schemas-go/hydro/schemas/github/security_center/v0"
	oldtshydro "github.com/github/hydro-schemas-go/hydro/schemas/turboscan/v0"

	"github.com/github/turboscan/ts/hydro/topics"

	"github.com/pkg/errors"
)

type HydroPublisher struct {
	publisher *hydro.Publisher
}

func New(kc hydro.KafkaConfig, sc stats.Client, sinkConfig ...hydro.KafkaSinkOption) (*HydroPublisher, error) {
	sink, err := hydro.NewKafkaSink(kc, sinkConfig...)
	if err != nil {
		return nil, err
	}
	p, err := hydro.NewPublisher(sink,
		hydro.WithTopicFormat(hydro.TopicFormatV2),
		hydro.WithPublisherStats(sc),
	)
	if err != nil {
		return nil, errors.Wrap(err, "creating hydro publisher")
	}

	return &HydroPublisher{publisher: p}, nil
}

func (p *HydroPublisher) Close() error {
	return p.publisher.Close()
}

func (p *HydroPublisher) Flush() error {
	return p.publisher.Flush()
}

func (p *HydroPublisher) NewAnalysis(_ context.Context, m *tshydro.Analysis) error {
	return p.publisher.Publish(m, hydro.WithTopic(topics.NewAnalysis))
}

func (p *HydroPublisher) ProcessedAnalysis(_ context.Context, m *tshydro.Analysis) error {
	// Note: We publish this on the old topic, taking advantage that both representations are wire compatible.
	return p.publisher.Publish(m, hydro.WithTopic(topics.ProcessedAnalysis))
}

func (p *HydroPublisher) FailedAnalysis(_ context.Context, m *tshydro.Analysis) error {
	return p.publisher.Publish(m, hydro.WithTopic(topics.FailedAnalysis))
}

func (p *HydroPublisher) AlertEvent(_ context.Context, m *oldtshydro.AlertEvent) error {
	return p.publisher.Publish(m, hydro.WithTopic(topics.AlertEvent))
}

func (p *HydroPublisher) AuditEntry(_ context.Context, m *auditLogHydro.AuditEntry) error {
	return p.publisher.Publish(m, hydro.WithTopic(topics.AuditEntry))
}

func (p *HydroPublisher) InsightsEntityBatchEvent(_ context.Context, m *insightshydro.InsightsEntityBatch) error {
	return p.publisher.Publish(m, hydro.WithTopic(topics.InsightsEntityBatch))
}

func (p *HydroPublisher) EnablementEvent(_ context.Context, m *tshydro.EnablementEvent) error {
	return p.publisher.Publish(m, hydro.WithTopic(topics.EnablementEvent))
}

func (p *HydroPublisher) CodeqlTelemetryMessage(_ context.Context, m *tshydro.CodeqlTelemetryMessage) error {
	return p.publisher.Publish(m, hydro.WithTopic(topics.CodeqlTelemetryMessage))
}

func (p *HydroPublisher) CodeqlMetricResultBatch(_ context.Context, messages []*tshydro.CodeqlMetricResult) error {
	batch := hydro.NewBatch()
	for _, m := range messages {
		batch.Add(m, hydro.WithTopic(topics.CodeqlMetricResult))
	}
	return p.publisher.PublishBatch(batch)
}

func (p *HydroPublisher) AutofixFixedAlertEvent(_ context.Context, m *tshydro.AutofixFixedAlertEvent) error {
	return p.publisher.Publish(m, hydro.WithTopic(topics.AutofixFixedAlertEvent))
}

func (p *HydroPublisher) AutofixUsageEvent(_ context.Context, m *tshydro.AutofixUsageEvent) error {
	return p.publisher.Publish(m, hydro.WithTopic(topics.AutofixUsageEvent))
}

func (p *HydroPublisher) AutofixGenerateEventBatch(_ context.Context, messages []*tshydro.AutofixGenerateEvent) error {
	// Don't try to publish the batch if there are no messages as it will error out
	if len(messages) == 0 {
		return nil
	}

	// Optimization to not create a batch if there is only a single message/event.
	if len(messages) == 1 {
		return p.publisher.Publish(messages[0], hydro.WithTopic(topics.AutofixGenerateEvent))
	}

	batch := hydro.NewBatch()
	for _, m := range messages {
		batch.Add(m, hydro.WithTopic(topics.AutofixGenerateEvent))
	}
	return p.publisher.PublishBatch(batch)
}

func (p *HydroPublisher) PublishDependabotAutofixResult(_ context.Context, m *tshydro.DependabotAutofixResult) error {
	return p.publisher.Publish(m, hydro.WithTopic(topics.DependabotAutofixResult))
}

func (p *HydroPublisher) AutofixGenerationCompletedEvent(_ context.Context, m *tshydro.AutofixGenerationCompleted) error {
	return p.publisher.Publish(m, hydro.WithTopic(topics.AutofixGenerationCompletedEvent))
}

func (p *HydroPublisher) WorkflowRunAnnotationsBatch(_ context.Context, messages []*tshydro.WorkflowRunAnnotation) error {
	// Don't try to publish the batch if there are no messages as it will error out
	if len(messages) == 0 {
		return nil
	}

	batch := hydro.NewBatch()
	for _, m := range messages {
		batch.Add(m, hydro.WithTopic(topics.WorkflowRunAnnotation))
	}
	return p.publisher.PublishBatch(batch)
}

func (p *HydroPublisher) ExpectedCodeqlRunEvent(_ context.Context, m *tshydro.ManagedAnalysesExpectedCodeqlRun) error {
	return p.publisher.Publish(m, hydro.WithTopic(topics.ManagedAnalysesExpectedCodeqlRun))
}

func (p *HydroPublisher) CodeqlRunEvent(_ context.Context, m *oldtshydro.CodeqlRun) error {
	return p.publisher.Publish(m, hydro.WithTopic(topics.CodeqlRun))
}

func (p *HydroPublisher) AlertLinksCreateBatch(_ context.Context, messages []*tshydro.AlertLinkCreate) error {
	// Don't try to publish the batch if there are no messages as it will error out
	if len(messages) == 0 {
		return nil
	}

	batch := hydro.NewBatch()
	for _, m := range messages {
		batch.Add(m, hydro.WithTopic(topics.AlertLinkCreate))
	}
	return p.publisher.PublishBatch(batch)
}

func (p *HydroPublisher) AlertLinksUpdateBatch(_ context.Context, messages []*tshydro.AlertLinkUpdate) error {
	// Don't try to publish the batch if there are no messages as it will error out
	if len(messages) == 0 {
		return nil
	}

	batch := hydro.NewBatch()
	for _, m := range messages {
		batch.Add(m, hydro.WithTopic(topics.AlertLinkUpdate))
	}
	return p.publisher.PublishBatch(batch)
}

func (p *HydroPublisher) PublishAutofixErrorOutcome(_ context.Context, m *tshydro.AutofixErrorOutcome) error {
	return p.publisher.Publish(m, hydro.WithTopic(topics.AutofixErrorOutcome))
}

func (p *HydroPublisher) PublishAutofixInvalidOutcome(_ context.Context, m *tshydro.AutofixInvalidOutcome) error {
	return p.publisher.Publish(m, hydro.WithTopic(topics.AutofixInvalidOutcome))
}
