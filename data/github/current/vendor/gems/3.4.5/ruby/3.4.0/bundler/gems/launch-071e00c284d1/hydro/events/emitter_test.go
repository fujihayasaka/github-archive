package events

import (
	"context"
	"testing"

	"github.com/golang/protobuf/proto"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestEmittedEventIsPublished(t *testing.T) {
	publisher := &fakePublisher{}

	emitter, err := NewEmitter(WithPublisher(publisher))
	require.NoError(t, err)
	emitter.EmitBlocking(context.TODO(), &fakeEvent{})

	assert.Len(t, publisher.events, 1, "number of messages")
}

func TestEmittedEventWithPartitionKeyIsPublished(t *testing.T) {
	publisher := &fakePublisher{}

	emitter, err := NewEmitter(WithPublisher(publisher))
	require.NoError(t, err)
	emitter.EmitBlockingWithPartitionKey(context.TODO(), &fakeEvent{}, "test-partition-key")

	assert.Len(t, publisher.events, 1, "number of messages")
}

func TestAsyncEmittedEventIsPublished(t *testing.T) {
	publisher := &fakePublisher{}

	emitter, err := NewEmitter(WithPublisher(publisher))
	require.NoError(t, err)
	emitter.Emit(&fakeEvent{})
	emitter.Close()

	assert.Len(t, publisher.events, 1, "number of messages")
}

type fakePublisher struct {
	events []proto.Message
}

func (p *fakePublisher) Publish(ctx context.Context, messages []proto.Message, partitionKey string) error {
	p.events = append(p.events, messages...)
	return nil
}

type fakeEvent struct{}

func (e *fakeEvent) GetHydroMessages() []proto.Message {
	msg := new(proto.Message)
	return []proto.Message{*msg}
}

func (e *fakeEvent) GetEventType() string {
	return "fake"
}

func (e *fakeEvent) GetSchemaName() string {
	return "test-schema"
}
