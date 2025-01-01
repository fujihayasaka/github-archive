package events

import (
	"context"

	ghhydro "github.com/github/hydro-client-go/v3/pkg/hydro"
	"github.com/golang/protobuf/proto" // nolint: staticcheck

	"github.com/github/launch/clients/hydro"
	"github.com/github/launch/observability/logger"
	"github.com/github/launch/observability/statter"
)

// EmitterOption is a func that adds more capabilities to the emitter.
type EmitterOption func(*Emitter)

// WithPublisher customizes the publisher used by an emitter.
func WithPublisher(publisher Publisher) EmitterOption {
	return func(e *Emitter) {
		e.publisher = publisher
	}
}

// WithKafkaPublisher is the option to use kafka as the event publisher
func WithKafkaPublisher(sink *ghhydro.KafkaSink, site ghhydro.Site, log logger.Logger, statter statter.Statter) (EmitterOption, error) {
	publisher, err := hydro.NewKafkaPublisher(sink, site, log, statter)
	if err != nil {
		return nil, err
	}

	return WithPublisher(publisher), nil
}

// WithNullPublisher is the option to use if you want to use a no-op hydro publisher.
func WithNullPublisher() EmitterOption {
	publisher := &nullPublisher{}
	return WithPublisher(publisher)
}

type nullPublisher struct{}

func (*nullPublisher) Publish(_ context.Context, _ []proto.Message, _ string) error {
	return nil
}

// WithLogger sets up a logger for the emitter to use. If this is not provided, the emitter will use a null logger.
func WithLogger(log logger.Logger) EmitterOption {
	return func(e *Emitter) {
		e.log = log
	}
}

// WithStatter sets up a statsd client for hydro to use. If this is not provided, the emitter will not emit statter.
func WithStatter(statter statter.Statter) EmitterOption {
	return func(e *Emitter) {
		e.stats = statter
	}
}
