package dag

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/github/github-telemetry-go/log"
	kafkaMocks "github.com/github/migrations-vnext/internal/pkg/kafka/mocks"
	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/types/known/timestamppb"
)

func Test_Worker_handleEventNode(t *testing.T) {
	// Event is intentionally incomplete. We don't need the full struct for this test.
	event := &v1.Event{
		EventId:          "test-id",
		EventAction:      v1.EventAction_EVENT_ACTION_EDITED,
		ResourceId:       "https://github.dev/monalisa",
		Timestamp:        &timestamppb.Timestamp{Seconds: time.Now().Unix()},
		MigrationContext: &v1.MigrationContext{EnterpriseId: 1},
	}

	marshaledEvent, err := proto.Marshal(event)
	require.NoError(t, err)

	tests := map[string]struct {
		gets                 Node
		setupEventProducerFn func(p *kafkaMocks.Producer)
		setupObjectStoreFn   func(o *MockObjectStore)
		wantsErr             bool
		wantsErrSubstr       string
	}{
		"should return an error when the node kind is not EventNode": {
			gets:           Node{ID: "test-id", Kind: ResourceNode},
			wantsErr:       true,
			wantsErrSubstr: "EventNode handler received invalid kind",
		},
		"should return an error when fetching the event returns an error": {
			gets: Node{ID: "test-id", Kind: EventNode},
			setupObjectStoreFn: func(o *MockObjectStore) {
				o.On("GetPayload", mock.IsType(context.Background()), "enterprise:1", "test-id").Return(nil, errors.New("test error"))
			},
			wantsErr:       true,
			wantsErrSubstr: "failed to get event payload",
		},
		"should return an error when writing to Kafka returns an error": {
			gets: Node{ID: "test-id", Kind: EventNode},
			setupEventProducerFn: func(p *kafkaMocks.Producer) {
				p.On("Produce", mock.IsType(context.Background()), mock.Anything).Return(errors.New("test error"))
			},
			setupObjectStoreFn: func(o *MockObjectStore) {
				o.On("GetPayload", mock.IsType(context.Background()), "enterprise:1", "test-id").Return(marshaledEvent, nil)
			},
			wantsErr:       true,
			wantsErrSubstr: "failed to produce event",
		},
		"should return nil when the node is successfully handled": {
			gets: Node{ID: "test-id", Kind: EventNode},
			setupEventProducerFn: func(p *kafkaMocks.Producer) {
				p.On("Produce", mock.IsType(context.Background()), mock.AnythingOfType("[]uint8")).Return(nil)
			},
			setupObjectStoreFn: func(o *MockObjectStore) {
				o.On("GetPayload", mock.IsType(context.Background()), "enterprise:1", "test-id").Return(marshaledEvent, nil)
			},
		},
	}

	for name, test := range tests {
		t.Run(name, func(t *testing.T) {
			eventProducer := kafkaMocks.NewProducer(t)
			objectStore := NewMockObjectStore(t)
			if test.setupEventProducerFn != nil {
				test.setupEventProducerFn(eventProducer)
			}
			if test.setupObjectStoreFn != nil {
				test.setupObjectStoreFn(objectStore)
			}
			w := &Worker{
				logger:        log.NewNullLogger(),
				eventProducer: eventProducer,
				objectStore:   objectStore,
			}

			err := w.handleEventNode(context.Background(), "enterprise:1", test.gets)
			require.Equal(t, test.wantsErr, err != nil)

			eventProducer.AssertExpectations(t)
			objectStore.AssertExpectations(t)

			if test.wantsErr {
				assert.Contains(t, err.Error(), test.wantsErrSubstr)
			} else {
				// I couldn't find a great way to do this natively with the mock. This is a bit
				// hacky, but ensures that the payload was properly encoded, and that when decoded,
				// matches our expected Event.
				var e v1.Event
				require.NoError(t, proto.Unmarshal(eventProducer.Calls[0].Arguments[1].([]byte), &e))
				assert.EqualExportedValues(t, event, &e)
			}
		})
	}
}

func Test_Worker_handleResourceNode(t *testing.T) {
	tests := map[string]struct {
		gets                    Node
		setupObjectStoreFn      func(o *MockObjectStore)
		setupResourceProducerFn func(p *kafkaMocks.Producer)
		wantsErr                bool
		wantsErrSubstr          string
	}{
		"should return an error when the node kind is not ResourceNode": {
			gets:           Node{ID: "test-id", Kind: EventNode},
			wantsErr:       true,
			wantsErrSubstr: "ResourceNode handler received invalid kind",
		},
		"should return an error when fetching the object payload returns an error": {
			gets: Node{ID: "test-id", Kind: ResourceNode},
			setupObjectStoreFn: func(o *MockObjectStore) {
				o.On("GetPayload", mock.IsType(context.Background()), "enterprise:1", "test-id").Return(nil, errors.New("test error"))
			},
			wantsErr:       true,
			wantsErrSubstr: "failed to get payload",
		},
		"should return an error when writing to Kafka returns an error": {
			gets: Node{ID: "test-id", Kind: ResourceNode},
			setupObjectStoreFn: func(o *MockObjectStore) {
				o.On("GetPayload", mock.IsType(context.Background()), "enterprise:1", "test-id").Return([]byte("test payload"), nil)
			},
			setupResourceProducerFn: func(p *kafkaMocks.Producer) {
				p.On("Produce", mock.IsType(context.Background()), []byte("test payload")).Return(errors.New("test error"))
			},
			wantsErr:       true,
			wantsErrSubstr: "failed to produce payload",
		},
		"should return nil when the node is successfully handled": {
			gets: Node{ID: "test-id", Kind: ResourceNode},
			setupObjectStoreFn: func(o *MockObjectStore) {
				o.On("GetPayload", mock.IsType(context.Background()), "enterprise:1", "test-id").Return([]byte("test payload"), nil)
			},
			setupResourceProducerFn: func(p *kafkaMocks.Producer) {
				p.On("Produce", mock.IsType(context.Background()), []byte("test payload")).Return(nil)
			},
		},
		"should use object store instead of inline to load resource": {
			gets: Node{ID: "test-id", Kind: ResourceNode},
			setupObjectStoreFn: func(o *MockObjectStore) {
				o.On("GetPayload", mock.IsType(context.Background()), "enterprise:1", "test-id").Return(make([]byte, maxKafkaSize+1), nil)
			},
			setupResourceProducerFn: func(p *kafkaMocks.Producer) {
				expectedResource := v1.Resource{
					Location: v1.ResourceLocationType_RESOURCE_LOCATION_TYPE_OBJECT_STORE,
					ObjectStore: &v1.ResourceLocationObjectStore{
						Key:  "test-id",
						Size: maxKafkaSize + 1,
					}}
				payload, err := proto.Marshal(&expectedResource)
				require.NoError(t, err)
				p.On("Produce", mock.IsType(context.Background()), payload).Return(nil)
			},
		},
	}

	for name, test := range tests {
		t.Run(name, func(t *testing.T) {
			objStore := NewMockObjectStore(t)
			resourceProducer := kafkaMocks.NewProducer(t)
			if test.setupObjectStoreFn != nil {
				test.setupObjectStoreFn(objStore)
			}
			if test.setupResourceProducerFn != nil {
				test.setupResourceProducerFn(resourceProducer)
			}
			w := &Worker{
				logger:           log.NewNullLogger(),
				objectStore:      objStore,
				resourceProducer: resourceProducer,
			}

			err := w.handleResourceNode(context.Background(), "enterprise:1", test.gets)
			require.Equal(t, test.wantsErr, err != nil)

			objStore.AssertExpectations(t)
			resourceProducer.AssertExpectations(t)

			if test.wantsErr {
				assert.Contains(t, err.Error(), test.wantsErrSubstr)
			}
		})
	}
}
