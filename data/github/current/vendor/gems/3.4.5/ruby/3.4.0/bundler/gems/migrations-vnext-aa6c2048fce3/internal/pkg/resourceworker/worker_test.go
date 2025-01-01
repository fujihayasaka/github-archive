package resourceworker

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/cenkalti/backoff/v4"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	kafkaMocks "github.com/github/migrations-vnext/internal/pkg/kafka/mocks"
	"github.com/github/migrations-vnext/internal/pkg/resource"
	"github.com/github/migrations-vnext/internal/pkg/resource/mocks"
	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
	"github.com/twitchtv/twirp"
	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/types/known/timestamppb"
)

func Test_shouldSendToDeadLetter(t *testing.T) {
	type args struct {
		err error
	}
	tests := []struct {
		name string
		args args
		want bool
	}{
		{
			name: "nil error is not send to dead letter",
			args: args{err: nil},
			want: false,
		},
		{
			name: "twirp cancelled error is not sent to dead letter",
			args: args{err: twirp.NewError(twirp.Canceled, "canceled")},
			want: false,
		},
		{
			name: "non-cancelled twirp error is sent to dead letter",
			args: args{err: twirp.NewError(twirp.Internal, "internal")},
			want: true,
		},
		{
			name: "initial_organization_settings_error is sent to dead letter",
			args: args{err: &resource.InitialOrganizationSettingsError{Errors: []string{"error"}}},
			want: true,
		},
		{
			name: "initial_repository_settings_error is sent to dead letter",
			args: args{err: &resource.InitialRepositorySettingsError{Err: assert.AnError}},
			want: true,
		},
		{
			name: "partial_batch_error is sent to dead letter",
			args: args{err: &resource.PartialBatchError{}},
			want: true,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			assert.Equalf(t, tt.want, shouldSendToDeadLetter(tt.args.err), "shouldSendToDeadLetter(%v)", tt.args.err)
		})
	}
}

func TestWorker_processMsg(t *testing.T) {
	someTime := time.Date(2023, 1, 1, 0, 0, 0, 0, time.UTC)
	nowFn = func() time.Time {
		return someTime
	}

	someResource := &v1.Resource{Resource: &v1.Resource_Team{Team: &v1.Team{ResourceId: "test-id"}}}
	someMarshaledResource, err := proto.Marshal(someResource)
	require.NoError(t, err)

	someFailedResource := &v1.FailedResource{
		ErrorMessage: twirp.NewError(twirp.Internal, "internal").Error(),
		FailedAt:     timestamppb.New(someTime),
		Resource:     &v1.Resource{Resource: &v1.Resource_Team{Team: &v1.Team{ResourceId: "test-id"}}},
	}
	someMarshaledFailedResource, err := proto.Marshal(someFailedResource)
	require.NoError(t, err)

	someDehydratedResource := &v1.Resource{
		Location: v1.ResourceLocationType_RESOURCE_LOCATION_TYPE_OBJECT_STORE,
		ObjectStore: &v1.ResourceLocationObjectStore{
			Key:  "test-id",
			Size: 5_000_000,
		},
		MigrationContext: &v1.MigrationContext{
			EnterpriseId: 1,
		},
	}
	someMarshaledDehydratedResource, err := proto.Marshal(someDehydratedResource)
	require.NoError(t, err)

	matchResource := mock.MatchedBy(func(r *v1.Resource) bool {
		return proto.Equal(r, someResource)
	})
	matchFailedResource := mock.MatchedBy(func(f []byte) bool {
		return assert.Equal(t, someMarshaledFailedResource, f)
	})

	tests := []struct {
		setupLoaderFn     func(l *mocks.Loader)
		setupProducerFn   func(p *kafkaMocks.Producer)
		setupObjectStore  func(o *MockObjectStore)
		name              string
		ctx               context.Context
		msg               []byte
		wantsErr          bool
		wantsErrSubstring string
	}{
		{
			name:     "should succeed when resource is loaded and no retries are needed",
			ctx:      context.Background(),
			msg:      someMarshaledResource,
			wantsErr: false,
			setupLoaderFn: func(l *mocks.Loader) {
				l.On("LoadResource", mock.Anything, matchResource).Return(nil).Once()
			},
		},
		{
			name:     "should succeed when resource is hydrated from object store and is loaded with no retries",
			ctx:      context.Background(),
			msg:      someMarshaledDehydratedResource,
			wantsErr: false,
			setupLoaderFn: func(l *mocks.Loader) {
				l.On("LoadResource", mock.Anything, matchResource).Return(nil).Once()
			},
			setupObjectStore: func(o *MockObjectStore) {
				o.On("GetPayload", mock.Anything, "enterprise:1", "test-id").Return(someMarshaledResource, nil)
			},
		},
		{
			name:     "should succeed when resource is loaded and a retry is needed",
			ctx:      context.Background(),
			msg:      someMarshaledResource,
			wantsErr: false,
			setupLoaderFn: func(l *mocks.Loader) {
				l.On("LoadResource", mock.Anything, matchResource).Return(assert.AnError).Once()
				l.On("LoadResource", mock.Anything, matchResource).Return(nil).Once()
			},
		},
		{
			name:     "should return an error when the resource can't be loaded after all retries",
			ctx:      context.Background(),
			msg:      someMarshaledResource,
			wantsErr: true,
			setupLoaderFn: func(l *mocks.Loader) {
				l.On("LoadResource", mock.Anything, matchResource).Return(assert.AnError)
			},
			wantsErrSubstring: "failed to load resource",
		},
		{
			name:     "should return an error when dead letter producer is not configured",
			ctx:      context.Background(),
			msg:      someMarshaledResource,
			wantsErr: true,
			setupLoaderFn: func(l *mocks.Loader) {
				l.
					On("LoadResource", mock.Anything, matchResource).
					Return(twirp.NewError(twirp.Internal, "internal"))
			},
			wantsErrSubstring: "failed to load resource",
		},
		{
			name:     "should return an error when dead letter producer fails to produce",
			ctx:      context.Background(),
			msg:      someMarshaledResource,
			wantsErr: true,
			setupLoaderFn: func(l *mocks.Loader) {
				l.
					On("LoadResource", mock.Anything, matchResource).
					Return(twirp.NewError(twirp.Internal, "internal"))
			},
			setupProducerFn: func(p *kafkaMocks.Producer) {
				p.On("Produce", mock.Anything, mock.Anything).Return(errors.New("test error"))
			},
			wantsErrSubstring: "failed to send resource to dead letter",
		},
		{
			name:     "should send resource to dead letter",
			ctx:      context.Background(),
			msg:      someMarshaledResource,
			wantsErr: false,
			setupLoaderFn: func(l *mocks.Loader) {
				l.
					On("LoadResource", mock.Anything, matchResource).
					Return(twirp.NewError(twirp.Internal, "internal"))
			},
			setupProducerFn: func(p *kafkaMocks.Producer) {
				p.On("Produce", mock.Anything, matchFailedResource).Return(nil)
			},
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			w := &Worker{
				resourceTracker: &tracker{logger: log.NewNullLogger()},
				backoffPolicy: func() backoff.BackOff {
					return backoff.NewExponentialBackOff(backoff.WithMaxElapsedTime(1 * time.Second))
				},
				logger:  log.NewNullLogger(),
				statter: stats.NullStatter,
			}
			if tt.setupLoaderFn != nil {
				loader := mocks.NewLoader(t)
				tt.setupLoaderFn(loader)
				w.loader = loader
			}
			if tt.setupProducerFn != nil {
				producer := kafkaMocks.NewProducer(t)
				tt.setupProducerFn(producer)
				w.deadLetterProducer = producer
			}
			if tt.setupObjectStore != nil {
				objectStore := new(MockObjectStore)
				tt.setupObjectStore(objectStore)
				w.objectStore = objectStore
			}
			err := w.processMsg(tt.ctx, tt.msg)
			if tt.wantsErr {
				require.Error(t, err)
				assert.Contains(t, err.Error(), tt.wantsErrSubstring)
			} else {
				assert.NoError(t, err)
			}
		})
	}
}
