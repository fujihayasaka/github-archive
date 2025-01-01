package eventworker

import (
	"context"
	"testing"
	"time"

	"github.com/cenkalti/backoff/v4"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	"github.com/github/migrations-vnext/internal/pkg/events/mocks"
	kafkaMocks "github.com/github/migrations-vnext/internal/pkg/kafka/mocks"
	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
	"github.com/twitchtv/twirp"
	gproto "google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/types/known/timestamppb"
)

func TestDeadLetterWorker_processEvent(t *testing.T) {
	someTime := time.Date(2023, 1, 1, 0, 0, 0, 0, time.UTC)
	nowFn = func() time.Time {
		return someTime
	}
	_, err := gproto.Marshal(&v1.Event{})
	require.NoError(t, err)
	someFailedEvent := &v1.FailedEvent{
		ErrorMessage:     twirp.NewError(twirp.Internal, "internal").Error(),
		RetriesAttempted: 6,
		FailedAt:         timestamppb.New(someTime),
		Event:            &v1.Event{},
	}
	someMarshaledFailedEvent, err := gproto.Marshal(someFailedEvent)
	require.NoError(t, err)

	t.Run("event is successfully loaded at first attempt", func(t *testing.T) {
		loader := &mocks.Loader{}
		loader.
			On("LoadEvent", mock.Anything, mock.IsType(someFailedEvent.Event)).
			Return(nil)

		w := &DeadLetterWorker{
			backoffPolicy: func() backoff.BackOff {
				return backoff.NewExponentialBackOff(backoff.WithMaxElapsedTime(1 * time.Second))
			},
			loader:  loader,
			logger:  log.NewNullLogger(),
			statter: stats.NullStatter,
		}

		err := w.processEvent(context.Background(), someMarshaledFailedEvent)
		require.NoError(t, err)
		assert.Nil(t, w.firstEvent)
	})

	t.Run("event is successfully loaded on second iteration", func(t *testing.T) {
		loader := &mocks.Loader{}
		loader.
			On("LoadEvent", mock.Anything, mock.IsType(someFailedEvent.Event)).
			Return(nil)

		w := &DeadLetterWorker{
			backoffPolicy: func() backoff.BackOff {
				return backoff.NewExponentialBackOff(backoff.WithMaxElapsedTime(1 * time.Second))
			},
			loader:     loader,
			logger:     log.NewNullLogger(),
			statter:    stats.NullStatter,
			firstEvent: someFailedEvent,
		}

		err := w.processEvent(context.Background(), someMarshaledFailedEvent)
		require.NoError(t, err)
		assert.Nil(t, w.firstEvent)
	})

	t.Run("event is successfully re-enqueued on load failure", func(t *testing.T) {
		// expectedFailedEvent is the event that should be re-enqueued
		// with the new error message and the number of retries attempted incremented.
		expectedFailedEvent := &v1.FailedEvent{
			ErrorMessage:     assert.AnError.Error(),
			RetriesAttempted: 7,
			FailedAt:         timestamppb.New(someTime),
			Event:            &v1.Event{},
		}

		loader := &mocks.Loader{}
		loader.
			On("LoadEvent", mock.Anything, mock.IsType(someFailedEvent.Event)).
			Return(assert.AnError) // Force load failure

		producer := kafkaMocks.NewProducer(t)
		producer.
			On("Produce", mock.Anything, mock.MatchedBy(func(f []byte) bool {
				var r v1.FailedEvent
				err := gproto.Unmarshal(f, &r)
				require.NoError(t, err)
				return gproto.Equal(expectedFailedEvent, &r)
			})).
			Return(nil)

		w := &DeadLetterWorker{
			backoffPolicy: func() backoff.BackOff {
				return backoff.NewExponentialBackOff(backoff.WithMaxElapsedTime(2 * time.Second))
			},
			loader:   loader,
			producer: producer,
			logger:   log.NewNullLogger(),
			statter:  stats.NullStatter,
		}

		err = w.processEvent(context.Background(), someMarshaledFailedEvent)
		require.NoError(t, err)
		assert.True(t, gproto.Equal(expectedFailedEvent, w.firstEvent))
		// Backoff policy should have allowed the LoadEvent to be called a number of times.
		assert.Greater(t, len(loader.Calls), 2)
	})
}

func TestDeadLetterWorker_handleError(t *testing.T) {
	someTime := time.Date(2023, 1, 1, 0, 0, 0, 0, time.UTC)
	nowFn = func() time.Time {
		return someTime
	}
	someFailedEvent := &v1.FailedEvent{
		ErrorMessage:     twirp.NewError(twirp.Internal, "internal").Error(),
		RetriesAttempted: 6,
		FailedAt:         timestamppb.New(time.Now()),
		Event:            &v1.Event{},
	}
	expectedNewFailedEvent := &v1.FailedEvent{
		ErrorMessage:     assert.AnError.Error(),
		RetriesAttempted: 7,
		FailedAt:         timestamppb.New(someTime),
		Event:            &v1.Event{},
	}
	matchNewFailedResource := mock.MatchedBy(func(f []byte) bool {
		var e v1.FailedEvent
		err := gproto.Unmarshal(f, &e)
		require.NoError(t, err)
		return gproto.Equal(expectedNewFailedEvent, &e)
	})

	producer := kafkaMocks.NewProducer(t)
	producer.On("Produce", mock.Anything, matchNewFailedResource).Return(nil)

	w := &DeadLetterWorker{
		producer: producer,
		logger:   log.NewNullLogger(),
		statter:  stats.NullStatter,
	}

	err := w.handleError(context.Background(), someFailedEvent, assert.AnError)
	require.NoError(t, err)
	assert.True(t, gproto.Equal(expectedNewFailedEvent, w.firstEvent))
}
