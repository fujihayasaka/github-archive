package hydro

import (
	"context"

	"github.com/github/hydro-client-go/v3/pkg/hydro"
	ghhydro "github.com/github/hydro-client-go/v3/pkg/hydro"
	"github.com/golang/protobuf/proto" // nolint: staticcheck

	"github.com/github/launch/observability/logger"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/pkg/panicmultierrgroup"
)

type kafkaClient struct {
	publisher kafkaPublisher
	log       logger.Logger
	statter   statter.Statter
}

type kafkaPublisher interface {
	Publish(message proto.Message, opts ...ghhydro.PublishOption) error
}

// Publish sends the encoded events to kafka.
// Context is not used by github/hydro-client-go, but is required to satisfy the Publisher interface
func (kc *kafkaClient) Publish(_ context.Context, messages []proto.Message, partitionKey string) error {
	errGroup := &panicmultierrgroup.Group{}

	for _, message := range messages {
		message := message
		errGroup.Go(func() error {
			var err error

			if partitionKey != "" {
				err = kc.publisher.Publish(message, ghhydro.WithPartitionKey(partitionKey))
			} else {
				err = kc.publisher.Publish(message)
			}
			if err != nil {
				return err
			}

			return nil
		})
	}

	if errs := errGroup.Wait(); errs.ErrorOrNil() != nil {
		return errs
	}

	return nil
}

func NewKafkaPublisher(sink *ghhydro.KafkaSink, site ghhydro.Site, log logger.Logger, statter statter.Statter) (*kafkaClient, error) {
	publisher, err := ghhydro.NewPublisher(sink, site, hydro.WithPublisherStats(statter.Client()))
	if err != nil {
		return nil, err
	}

	return &kafkaClient{
		publisher: publisher,
		log:       log,
		statter:   statter,
	}, nil
}
