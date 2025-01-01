package broadcaster

import (
	"context"
	"fmt"
	"sync"
	"testing"
	"time"

	"github.com/github/authnd/internal/common/diagnostics"
	"github.com/github/go-stats"
	"github.com/github/go-stats/mocks"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
	"go.uber.org/goleak"
)

func TestNewSession(t *testing.T) {
	b := NewBroadcaster()

	s1 := b.NewSession("broadcast-key", "")
	assert.Len(t, s1.String(), 36)
	assert.Equal(t, "broadcast-key", s1.key)

	s2 := b.NewSession("broadcast-key", "sidp")
	assert.Len(t, s2.String(), 41)
	assert.Equal(t, "sidp-", s2.String()[0:5])
	assert.Equal(t, "broadcast-key", s2.key)

	assert.Panics(t, func() {
		b.NewSession("", "whatever")
	})
}

func TestBroadcaster_TryListenBeforeTryBroadcastFails(t *testing.T) {
	b := NewBroadcaster()
	s := b.NewSession("bc1", "")
	_, ok := b.TryListen(context.Background(), s)
	assert.False(t, ok)
}

func TestBroadcaster_BroadcastWithThreeListeners(t *testing.T) {
	defer goleak.VerifyNone(t)

	mockStatter := mocks.Client{}
	defer mockStatter.AssertExpectations(t)

	mockStatter.Mock.On("Counter", "broadcaster.transmit_complete", stats.Tags{"result": "success"}, int64(1)).Once().Return()
	mockStatter.Mock.On("Histogram", "broadcaster.listeners", mock.AnythingOfType("stats.Tags"), int64(3)).Once().Return()
	ctx := diagnostics.WithStatter(context.Background(), &mockStatter)

	b := NewBroadcaster()
	value := "special message"

	s1 := b.NewSession("bc1", "")
	broadcastCh, ok := b.TryBroadcast(ctx, s1)
	require.True(t, ok)
	t.Logf("ready to broadcast from %s", s1.String())

	var wg sync.WaitGroup
	for i := 0; i < 3; i++ {
		ls := b.NewSession("bc1", fmt.Sprintf("ls%d", i))
		_, ok := b.TryBroadcast(ctx, ls)
		require.False(t, ok)
		t.Logf("joined broadcast %s", ls.String())

		wg.Add(1)
		go func(listenerSession Session) {
			defer wg.Done()
			t.Logf("dialing to listen %s", listenerSession.String())
			lsCh, ok := b.TryListen(ctx, listenerSession)
			require.True(t, ok)
			t.Logf("ready to listen on %s", listenerSession.String())

			result := <-lsCh
			assert.Equal(t, value, result.Data.(string))
			assert.Equal(t, s1.String(), result.BroadcasterID)
			assert.NoError(t, result.Err)
		}(ls)
	}

	t.Log("broadcasting result")
	broadcastCh <- Result{Data: value}

	t.Log("waiting on listeners")
	wg.Wait()

	waitForStationToClose(t, b, "bc1")
}

func TestBroadcaster_StationsAreIsolated(t *testing.T) {
	defer goleak.VerifyNone(t)

	mockStatter := mocks.Client{}
	defer mockStatter.AssertExpectations(t)

	mockStatter.Mock.On("Counter", "broadcaster.transmit_complete", stats.Tags{"result": "success"}, int64(1)).Times(2).Return()
	mockStatter.Mock.On("Histogram", "broadcaster.listeners", mock.AnythingOfType("stats.Tags"), int64(1)).Once().Return()
	mockStatter.Mock.On("Histogram", "broadcaster.listeners", mock.AnythingOfType("stats.Tags"), int64(0)).Once().Return()
	ctx := diagnostics.WithStatter(context.Background(), &mockStatter)

	b := NewBroadcaster()
	s1 := b.NewSession("bc1", "")
	s2 := b.NewSession("bc2", "")
	s3 := b.NewSession("bc1", "")

	ch1, ok := b.TryBroadcast(ctx, s1)
	require.True(t, ok)
	ch2, ok := b.TryBroadcast(ctx, s2)
	require.True(t, ok)

	_, ok = b.TryBroadcast(ctx, s3)
	require.False(t, ok)
	ch3, ok := b.TryListen(ctx, s3)
	require.True(t, ok)

	ch1 <- Result{Data: "1"}
	ch2 <- Result{Data: "2"}

	res := <-ch3
	assert.Equal(t, "1", res.Data.(string))

	waitForStationToClose(t, b, "bc1")
	waitForStationToClose(t, b, "bc2")
}

// broadcaster closed between TryBroadcast and TryListen is safe

func TestBroadcaster_ClosedBetweenTryBroadcastAndTryListen(t *testing.T) {
	defer goleak.VerifyNone(t)

	mockStatter := mocks.Client{}
	defer mockStatter.AssertExpectations(t)

	mockStatter.Mock.On("Counter", "broadcaster.transmit_complete", stats.Tags{"result": "success"}, int64(1)).Once().Return()
	mockStatter.Mock.On("Histogram", "broadcaster.listeners", mock.AnythingOfType("stats.Tags"), int64(1)).Once().Return()
	ctx := diagnostics.WithStatter(context.Background(), &mockStatter)

	b := NewBroadcaster()
	s1 := b.NewSession("bc1", "")
	s2 := b.NewSession("bc1", "")

	ch1, ok := b.TryBroadcast(ctx, s1)
	require.True(t, ok)
	_, ok = b.TryBroadcast(ctx, s2)
	require.False(t, ok)

	// send result after s2 has joined but before s2 started listened
	ch1 <- Result{Data: "1"}

	ch2, ok := b.TryListen(ctx, s2)
	require.True(t, ok)

	res := <-ch2
	assert.Equal(t, "1", res.Data.(string))

	waitForStationToClose(t, b, "bc1")
}

func TestBroadcaster_TryBroadcastFailsWhenNotJoinable(t *testing.T) {
	defer goleak.VerifyNone(t)

	b := NewBroadcaster()
	s1 := b.NewSession("bc1", "")
	s2 := b.NewSession("bc1", "")
	s3 := b.NewSession("bc1", "")
	s4 := b.NewSession("bc1", "")

	// broadcaster
	ch1, ok := b.TryBroadcast(context.Background(), s1)
	require.True(t, ok)

	// listener #1
	_, ok = b.TryBroadcast(context.Background(), s2)
	require.False(t, ok)
	ch2, ok := b.TryListen(context.Background(), s2)
	require.True(t, ok)

	// listener #2
	_, ok = b.TryBroadcast(context.Background(), s3)
	require.False(t, ok)
	ch3, ok := b.TryListen(context.Background(), s3)
	require.True(t, ok)

	// read from listener 1. broadcast should no longer be joinable
	ch1 <- Result{Data: "1"}
	res := <-ch2
	assert.Equal(t, "1", res.Data.(string))

	b.mu.RLock()
	assert.False(t, b.stations[s1.key].joinable)
	b.mu.RUnlock()

	// listener #3 cannot join
	_, ok = b.TryBroadcast(context.Background(), s4)
	require.False(t, ok)
	_, ok = b.TryListen(context.Background(), s4)
	require.False(t, ok)

	// read from second listener
	res = <-ch3
	assert.Equal(t, "1", res.Data.(string))

	waitForStationToClose(t, b, "bc1")
}

func TestBroadcaster_Cancelled(t *testing.T) {
	defer goleak.VerifyNone(t)

	b := NewBroadcaster()
	s1 := b.NewSession("bc1", "")
	s2 := b.NewSession("bc1", "")

	ctx, cancel := context.WithCancel(context.Background())

	_, ok := b.TryBroadcast(ctx, s1)
	require.True(t, ok)

	_, ok = b.TryBroadcast(ctx, s2)
	require.False(t, ok)
	ch, ok := b.TryListen(ctx, s2)
	require.True(t, ok)

	cancel()

	// listeners don't block when broadcaster's context is cancelled
	res := <-ch
	assert.Equal(t, ErrCancelled, res.Err)

	waitForStationToClose(t, b, "bc1")

}

func waitForStationToClose(t *testing.T, b *Broadcaster, stationKey string) {
	t.Helper()

	for i := 0; i < 20; i++ {
		<-time.After(1 * time.Millisecond)
		b.mu.RLock()
		_, ok := b.stations[stationKey]
		b.mu.RUnlock()
		if !ok {
			t.Logf("station closed after %dms", i+1)
			return
		}
	}
	t.Fatalf("station '%s' not closed after 20ms", stationKey)
}
