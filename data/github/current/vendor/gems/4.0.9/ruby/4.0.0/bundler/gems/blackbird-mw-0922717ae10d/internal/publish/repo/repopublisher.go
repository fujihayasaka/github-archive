package repo

import (
	"context"
	"time"

	"github.com/IBM/sarama"
	"github.com/github/go-kvp"
	"github.com/github/go-telemetry/logging"
	"github.com/github/hydro-client-go/v7/pkg/hydro"
	search_pb "github.com/github/hydro-schemas-go/hydro/schemas/github/search/v0"
	hydro_entities "github.com/github/hydro-schemas-go/hydro/schemas/github/v1/entities"

	"github.com/github/blackbird-mw/internal/routing"
	"github.com/github/blackbird-mw/internal/types"
)

var encoder = hydro.NewDefaultEncoder()

// Publisher publishes a single repository to the onboard topic.
type Publisher struct {
	producer   sarama.SyncProducer
	partitions uint32
}

func NewPublisher(producer sarama.SyncProducer, partitions uint32) *Publisher {
	return &Publisher{producer, partitions}
}

func (r *Publisher) Close() {
	r.producer.Close()
}

func (r *Publisher) Publish(ctx context.Context, repoID types.RepoID, corpusName string) error {
	return r.PublishChange(ctx, repoID, search_pb.RepositoryChanged_ADMIN_PUSHED, corpusName)
}

func (r *Publisher) PublishChange(ctx context.Context, repoID types.RepoID, change search_pb.RepositoryChanged_Change, corpusName string) error {
	if corpusName != "" {
		_, err := routing.CorpusFromString(corpusName)
		if err != nil {
			return err
		}
	}

	event := &search_pb.RepositoryChanged{
		Change: change,
		Repository: &hydro_entities.Repository{
			Id: uint32(repoID),
		},
		BlackbirdTargetCorpus: corpusName,
	}

	payload, err := encoder.Encode(event, time.Now())
	if err != nil {
		return err
	}

	msg := &sarama.ProducerMessage{
		Topic:     routing.OnboardSourceTopic,
		Partition: int32(types.PartitionID(repoID, r.partitions)),
		Value:     sarama.ByteEncoder(payload),
	}
	partition, offset, err := r.producer.SendMessage(msg)
	if err != nil {
		logging.Error(ctx, "error publishing message to request indexing", kvp.Uint("repo_id", uint(repoID)), kvp.Err(err))
		return err
	}

	logging.Info(
		ctx,
		"published message to request indexing",
		kvp.Uint("repo_id", uint(repoID)),
		kvp.String("topic", routing.OnboardSourceTopic),
		kvp.Int("partition", int(partition)),
		kvp.Int64("offset", offset),
	)
	return nil
}
