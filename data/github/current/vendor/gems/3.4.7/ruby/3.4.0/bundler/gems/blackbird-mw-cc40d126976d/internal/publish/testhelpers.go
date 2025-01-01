package publish

import (
	"testing"

	"github.com/IBM/sarama"
	hydroschemas "github.com/github/hydro-client-go/v7/generated/hydro/v1"
	"github.com/golang/protobuf/proto" //nolint:staticcheck
	"github.com/stretchr/testify/require"

	searchpb "github.com/github/hydro-schemas-go/hydro/schemas/github/search/v0"
)

func DeserializeMessage(t *testing.T, msg *sarama.ProducerMessage) *searchpb.RepositoryChanged {
	t.Helper()

	event := searchpb.RepositoryChanged{}
	envelope := hydroschemas.Envelope{}

	err := proto.Unmarshal([]byte(msg.Value.(sarama.ByteEncoder)), &envelope)
	require.NoError(t, err)

	err = proto.Unmarshal(envelope.Message, &event)
	require.NoError(t, err)

	return &event
}

func DeserializeMessages(t *testing.T, messages []*sarama.ProducerMessage) []*searchpb.RepositoryChanged {
	t.Helper()

	out := []*searchpb.RepositoryChanged{}
	for _, msg := range messages {
		out = append(out, DeserializeMessage(t, msg))
	}

	return out
}
