package deltaingest

import (
	"fmt"
	"time"

	"github.com/IBM/sarama"
	"github.com/github/hydro-client-go/v7/pkg/hydro"
	blackbird "github.com/github/hydro-schemas-go/hydro/schemas/blackbird/v0"

	"github.com/github/blackbird-mw/internal/routing"
)

func EncodeSnapshotMessage(topic routing.SnapshotTopic, snapshot *blackbird.SnapshotTreeUpdate) (*sarama.ProducerMessage, error) {
	payload, err := encoder.Encode(snapshot, time.Now())
	if err != nil {
		return nil, fmt.Errorf("failed to encode snapshot hydro message on topic %s: %w", topic.Name(), err)
	}

	return &sarama.ProducerMessage{Topic: topic.Name(), Value: sarama.ByteEncoder(payload)}, nil
}

var encoder = hydro.NewDefaultEncoder()
