package hydro

import (
	"context"
	"errors"
	"sync"
	"testing"

	ghhydro "github.com/github/hydro-client-go/v3/pkg/hydro"
	"github.com/golang/protobuf/proto"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	hydro "github.com/github/launch/hydro/schemas/github/actions/v0"
	"github.com/github/launch/observability"
)

func TestKafkaPublisherNoPartitionKey(t *testing.T) {
	kafka := newMockPublisher()
	obs := observability.NewNullObservability()
	publisher := &kafkaClient{
		publisher: kafka,
		log:       obs.Logger,
		statter:   obs.Statter,
	}
	msg := &hydro.WorkflowExecution{
		ExternalProviderReference: "some-random-id",
	}

	require.NoError(t, publisher.Publish(context.Background(), []proto.Message{msg}, ""))

	assert.Equal(t, 1, kafka.MessageCount())
	assert.True(t, kafka.HasMessage("some-random-id"))
	assert.False(t, kafka.HasPublishOptions())
}

func TestKafkaPublisherNoPartitionKeyOneError(t *testing.T) {
	kafka := newMockPublisher()
	obs := observability.NewNullObservability()
	publisher := &kafkaClient{
		publisher: kafka,
		log:       obs.Logger,
		statter:   obs.Statter,
	}
	msg := &hydro.WorkflowExecution{
		ExternalProviderReference: "some-random-id",
	}
	badmsg := &hydro.WorkflowExecution{
		ExternalProviderReference: "some-bad-message",
	}
	kafka.SetBadMessage("some-bad-message")

	msgs := []proto.Message{msg, msg, msg, badmsg}
	err := publisher.Publish(context.Background(), msgs, "")

	assert.Error(t, err)
	assert.True(t, kafka.HasMessage("some-random-id"))
	assert.Equal(t, 3, kafka.MessageCount())
}

func TestKafkaPublisherWithPartitionKey(t *testing.T) {
	kafka := newMockPublisher()
	obs := observability.NewNullObservability()
	publisher := &kafkaClient{
		publisher: kafka,
		log:       obs.Logger,
		statter:   obs.Statter,
	}
	msg := &hydro.WorkflowExecution{
		ExternalProviderReference: "some-random-id",
	}

	require.NoError(t, publisher.Publish(context.Background(), []proto.Message{msg}, "some-partition-key"))

	assert.Equal(t, 1, kafka.MessageCount())
	assert.True(t, kafka.HasMessage("some-random-id"))
	assert.True(t, kafka.HasPublishOptions())
}

type mockPublisher struct {
	messages       []proto.Message
	publishOptions []ghhydro.PublishOption
	badMessage     string
	mutex          sync.Mutex
}

func newMockPublisher() *mockPublisher {
	return &mockPublisher{
		messages:       []proto.Message{},
		publishOptions: []ghhydro.PublishOption{},
	}
}

// mockPublisher implements the kafka.Publisher interface
func (m *mockPublisher) Publish(msg proto.Message, options ...ghhydro.PublishOption) error {
	m.mutex.Lock()
	defer m.mutex.Unlock()

	if msg.(*hydro.WorkflowExecution).GetExternalProviderReference() == m.badMessage {
		return errors.New("Got bad message")
	}
	m.messages = append(m.messages, msg)
	m.publishOptions = append(m.publishOptions, options...)
	return nil
}

func (m *mockPublisher) SetBadMessage(msg string) {
	m.badMessage = msg
}

func (m *mockPublisher) MessageCount() int {
	return len(m.messages)
}

func (m *mockPublisher) HasMessage(ref string) bool {
	for _, msg := range m.messages {
		if msg.(*hydro.WorkflowExecution).GetExternalProviderReference() == ref {
			return true
		}
	}
	return false
}

func (m *mockPublisher) HasPublishOptions() bool {
	return len(m.publishOptions) > 0
}
