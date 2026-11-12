package github

import (
	"context"
	"io"
	"sync/atomic"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
)

func TestTokenRefreshCoordinator(t *testing.T) {
	t.Run("deduplicates concurrent refreshes for same key", func(t *testing.T) {
		coord := newTokenRefreshCoordinator()
		refreshStarted := make(chan struct{})
		releaseRefresh := make(chan struct{})
		var refreshCalls int32

		refreshFn := func(context.Context) (string, error) {
			atomic.AddInt32(&refreshCalls, 1)
			close(refreshStarted)
			<-releaseRefresh
			return "new-token", nil
		}

		result1 := make(chan string, 1)
		result2 := make(chan string, 1)
		err1 := make(chan error, 1)
		err2 := make(chan error, 1)

		go func() {
			token, callErr := coord.Refresh(context.Background(), "key1", refreshFn)
			result1 <- token
			err1 <- callErr
		}()

		<-refreshStarted

		go func() {
			token, callErr := coord.Refresh(context.Background(), "key1", refreshFn)
			result2 <- token
			err2 <- callErr
		}()

		// Give the second goroutine time to enter the coordinator
		time.Sleep(10 * time.Millisecond)
		close(releaseRefresh)

		require.Equal(t, "new-token", <-result1)
		require.NoError(t, <-err1)
		require.Equal(t, "new-token", <-result2)
		require.NoError(t, <-err2)
		require.Equal(t, int32(1), atomic.LoadInt32(&refreshCalls))
	})

	t.Run("independent keys refresh independently", func(t *testing.T) {
		coord := newTokenRefreshCoordinator()
		var refreshCalls int32

		refreshFn := func(context.Context) (string, error) {
			atomic.AddInt32(&refreshCalls, 1)
			return "token", nil
		}

		token1, err := coord.Refresh(context.Background(), "key1", refreshFn)
		require.NoError(t, err)
		require.Equal(t, "token", token1)

		token2, err := coord.Refresh(context.Background(), "key2", refreshFn)
		require.NoError(t, err)
		require.Equal(t, "token", token2)

		require.Equal(t, int32(2), atomic.LoadInt32(&refreshCalls))
	})

	t.Run("waiter respects context cancellation", func(t *testing.T) {
		coord := newTokenRefreshCoordinator()
		refreshStarted := make(chan struct{})
		blockForever := make(chan struct{})

		// Start a long-running refresh
		go func() {
			_, _ = coord.Refresh(context.Background(), "key1", func(context.Context) (string, error) {
				close(refreshStarted)
				<-blockForever
				return "token", nil
			})
		}()

		<-refreshStarted

		// Second caller with a cancelled context
		ctx, cancel := context.WithCancel(context.Background())
		cancel()

		_, err := coord.Refresh(ctx, "key1", func(context.Context) (string, error) {
			t.Fatal("should not be called")
			return "", nil
		})
		require.ErrorIs(t, err, context.Canceled)

		close(blockForever)
	})

	t.Run("allows new refresh after previous completes", func(t *testing.T) {
		coord := newTokenRefreshCoordinator()
		var refreshCalls int32

		for i := 0; i < 3; i++ {
			token, err := coord.Refresh(context.Background(), "key1", func(context.Context) (string, error) {
				atomic.AddInt32(&refreshCalls, 1)
				return "token", nil
			})
			require.NoError(t, err)
			require.Equal(t, "token", token)
		}

		require.Equal(t, int32(3), atomic.LoadInt32(&refreshCalls))
	})

	t.Run("propagates error to waiters", func(t *testing.T) {
		coord := newTokenRefreshCoordinator()
		refreshStarted := make(chan struct{})
		releaseRefresh := make(chan struct{})

		refreshFn := func(context.Context) (string, error) {
			close(refreshStarted)
			<-releaseRefresh
			return "", io.ErrUnexpectedEOF
		}

		err1 := make(chan error, 1)
		err2 := make(chan error, 1)

		go func() {
			_, callErr := coord.Refresh(context.Background(), "key1", refreshFn)
			err1 <- callErr
		}()

		<-refreshStarted

		go func() {
			_, callErr := coord.Refresh(context.Background(), "key1", refreshFn)
			err2 <- callErr
		}()

		time.Sleep(10 * time.Millisecond)
		close(releaseRefresh)

		require.ErrorIs(t, <-err1, io.ErrUnexpectedEOF)
		require.ErrorIs(t, <-err2, io.ErrUnexpectedEOF)
	})
}
