package dlworker

import (
	"context"
	"testing"
	"time"

	"github.com/cenkalti/backoff/v4"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	kafkaMocks "github.com/github/migrations-vnext/internal/pkg/kafka/mocks"
	"github.com/github/migrations-vnext/internal/pkg/resource/mocks"
	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
	"github.com/twitchtv/twirp"
	gproto "google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/types/known/timestamppb"
)

func TestWorker_processMsg(t *testing.T) {
	someTime := time.Date(2023, 1, 1, 0, 0, 0, 0, time.UTC)
	nowFn = func() time.Time {
		return someTime
	}
	someMarshaledResource, err := gproto.Marshal(&v1.Resource{Resource: &v1.Resource_Team{}})
	require.NoError(t, err)
	someFailedResource := &v1.FailedResource{
		ErrorMessage:     twirp.NewError(twirp.Internal, "internal").Error(),
		RetriesAttempted: 6,
		FailedAt:         timestamppb.New(someTime),
		Resource:         &v1.Resource{Resource: &v1.Resource_Team{}, MigrationContext: &v1.MigrationContext{EnterpriseId: 1}},
	}
	someMarshaledFailedResource, err := gproto.Marshal(someFailedResource)
	require.NoError(t, err)
	someDehydratedFailedResource := &v1.FailedResource{
		ErrorMessage:     twirp.NewError(twirp.Internal, "internal").Error(),
		RetriesAttempted: 6,
		FailedAt:         timestamppb.New(someTime),
		Resource: &v1.Resource{
			Location:         v1.ResourceLocationType_RESOURCE_LOCATION_TYPE_OBJECT_STORE,
			ObjectStore:      &v1.ResourceLocationObjectStore{Key: "test-key", Size: 1000},
			MigrationContext: &v1.MigrationContext{EnterpriseId: 1},
		},
	}
	someMarshaledDehydratedFailedResource, err := gproto.Marshal(someDehydratedFailedResource)
	require.NoError(t, err)

	t.Run("resource is successfully loaded at first attempt", func(t *testing.T) {
		loader := &mocks.Loader{}
		loader.
			On("LoadResource", mock.Anything, mock.IsType(someFailedResource.Resource)).
			Return(nil)

		w := &Worker{
			backoffPolicy: func() backoff.BackOff {
				return backoff.NewExponentialBackOff(backoff.WithMaxElapsedTime(1 * time.Second))
			},
			loader:  loader,
			logger:  log.NewNullLogger(),
			statter: stats.NullStatter,
		}

		err := w.processMsg(context.Background(), someMarshaledFailedResource)
		require.NoError(t, err)
		assert.Nil(t, w.firstResource)
	})

	t.Run("resource that is rehydrated from object store is successfully loaded", func(t *testing.T) {
		loader := &mocks.Loader{}
		loader.
			On("LoadResource", mock.Anything, mock.IsType(someFailedResource.Resource)).
			Return(nil)

		objectStore := &MockObjectStore{}
		objectStore.On("GetPayload", mock.Anything, "enterprise:1", "test-key").Return(someMarshaledResource, nil)

		w := &Worker{
			backoffPolicy: func() backoff.BackOff {
				return backoff.NewExponentialBackOff(backoff.WithMaxElapsedTime(1 * time.Second))
			},
			objectStore: objectStore,
			loader:      loader,
			logger:      log.NewNullLogger(),
			statter:     stats.NullStatter,
		}

		err := w.processMsg(context.Background(), someMarshaledDehydratedFailedResource)
		require.NoError(t, err)

		assert.Nil(t, w.firstResource)
	})

	t.Run("resource is successfully loaded on second iteration", func(t *testing.T) {
		loader := &mocks.Loader{}
		loader.
			On("LoadResource", mock.Anything, mock.IsType(someFailedResource.Resource)).
			Return(nil)

		w := &Worker{
			backoffPolicy: func() backoff.BackOff {
				return backoff.NewExponentialBackOff(backoff.WithMaxElapsedTime(1 * time.Second))
			},
			loader:        loader,
			firstResource: someFailedResource,
			logger:        log.NewNullLogger(),
			statter:       stats.NullStatter,
		}

		err := w.processMsg(context.Background(), someMarshaledFailedResource)
		require.NoError(t, err)
		assert.Nil(t, w.firstResource)
	})

	t.Run("resource is successfully re-enqueued on load failure", func(t *testing.T) {
		// expectedFailedResource is the resource that should be re-enqueued
		// with the new error message and the number of retries attempted updated
		expectedFailedResource := &v1.FailedResource{
			ErrorMessage:     assert.AnError.Error(),
			RetriesAttempted: 7,
			FailedAt:         timestamppb.New(someTime),
			Resource:         &v1.Resource{Resource: &v1.Resource_Team{}, MigrationContext: &v1.MigrationContext{EnterpriseId: 1}},
		}

		loader := &mocks.Loader{}
		loader.
			On("LoadResource", mock.Anything, mock.IsType(someFailedResource.Resource)).
			Return(assert.AnError) // Force load failure

		producer := kafkaMocks.NewProducer(t)
		producer.
			On("Produce", mock.Anything, mock.MatchedBy(func(f []byte) bool {
				var r v1.FailedResource
				err := gproto.Unmarshal(f, &r)
				require.NoError(t, err)
				return gproto.Equal(expectedFailedResource, &r)
			})).
			Return(nil)

		w := &Worker{
			backoffPolicy: func() backoff.BackOff {
				return backoff.NewExponentialBackOff(backoff.WithMaxElapsedTime(1 * time.Second))
			},
			loader:             loader,
			deadLetterProducer: producer,
			logger:             log.NewNullLogger(),
			statter:            stats.NullStatter,
		}

		err = w.processMsg(context.Background(), someMarshaledFailedResource)
		require.NoError(t, err)
		assert.True(t, gproto.Equal(expectedFailedResource, w.firstResource))
	})
}

func TestWorker_handleLoadError(t *testing.T) {
	someTime := time.Date(2023, 1, 1, 0, 0, 0, 0, time.UTC)
	nowFn = func() time.Time {
		return someTime
	}
	someFailedResource := &v1.FailedResource{
		ErrorMessage:     twirp.NewError(twirp.Internal, "internal").Error(),
		RetriesAttempted: 6,
		FailedAt:         timestamppb.New(time.Now()),
		Resource:         &v1.Resource{Resource: &v1.Resource_Team{Team: &v1.Team{ResourceId: "test-id"}}},
	}
	expectedNewFailedResource := &v1.FailedResource{
		ErrorMessage:     assert.AnError.Error(),
		RetriesAttempted: 7,
		FailedAt:         timestamppb.New(someTime),
		Resource:         &v1.Resource{Resource: &v1.Resource_Team{Team: &v1.Team{ResourceId: "test-id"}}},
	}
	matchNewFailedResource := mock.MatchedBy(func(f []byte) bool {
		var r v1.FailedResource
		err := gproto.Unmarshal(f, &r)
		require.NoError(t, err)
		return gproto.Equal(expectedNewFailedResource, &r)
	})

	producer := kafkaMocks.NewProducer(t)
	producer.On("Produce", mock.Anything, matchNewFailedResource).Return(nil)

	w := &Worker{
		deadLetterProducer: producer,
		logger:             log.NewNullLogger(),
		statter:            stats.NullStatter,
	}

	err := w.handleLoadError(context.Background(), someFailedResource, assert.AnError)
	require.NoError(t, err)
	assert.True(t, gproto.Equal(expectedNewFailedResource, w.firstResource))
}
