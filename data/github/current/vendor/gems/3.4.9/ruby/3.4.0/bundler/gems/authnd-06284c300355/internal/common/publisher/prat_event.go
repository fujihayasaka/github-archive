package publisher

import (
	"context"
	"fmt"
	"time"

	"github.com/github/authnd/internal/common/config"
	"github.com/github/authnd/internal/common/diagnostics"
	proto "github.com/github/authnd/internal/common/publisher/hydro/schemas/authnd/v0"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/hydro-client-go/v7/pkg/hydro"
	"github.com/pkg/errors"
)

type PratEventPublisher interface {
	PublishEvent(ctx context.Context, message proto.ProgrammaticAccessEvent) error
	Publisher
}

type pratEventPublisher struct {
	topic string
	Publisher
}

func NewPratEventPublisher(ctx context.Context, commonConfig *config.CommonConfig, withSink func(hydro.KafkaConfig) (hydro.Sink, error)) (PratEventPublisher, error) {
	publisher, err := NewPublisher(ctx, commonConfig, commonConfig.KafkaYukonBrokers, hydro.TopicFormatV2, withSink)
	if err != nil {
		return nil, errors.WithStack(err)
	}

	// Must use the production topic when publishing from canary
	topic := fmt.Sprintf("authnd.credential.%s.v0.ProgrammaticAccess.Event", commonConfig.DeploymentEnvironmentWithoutCanary())
	if commonConfig.IsProxima {
		topic = "authnd.credential.v0.ProgrammaticAccess.Event"
	}

	return &pratEventPublisher{
		Publisher: publisher,
		topic:     topic,
	}, nil
}

func (p *pratEventPublisher) PublishEvent(ctx context.Context, message proto.ProgrammaticAccessEvent) error {
	startTime := time.Now()
	err := p.PublishMessage(ctx, p.topic, &message)
	if err != nil {
		diagnostics.Statter(ctx).Counter("programmatic_access.event.publish.error", nil, 1)
		diagnostics.Logger(ctx).WithError(err).Error("PublishEvent failed to publish prat event message", kvp.Int64("gh.user.id", message.ActorId))
	}
	statter := diagnostics.Statter(ctx)
	statter.DistributionMs("programmatic_access.event.publish.duration", nil, time.Since(startTime))
	return err
}
