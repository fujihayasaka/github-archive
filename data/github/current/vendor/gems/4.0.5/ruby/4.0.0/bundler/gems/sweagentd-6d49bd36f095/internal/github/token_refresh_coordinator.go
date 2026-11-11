package github

import (
	"context"
	"sync"
)

// tokenRefreshCoordinator deduplicates concurrent token refreshes sharing the
// same cache key. When multiple transports (or clients) observe a 401 for the
// same key simultaneously, only one actually calls the underlying refresh
// function; the others wait for the result. This prevents thundering-herd
// invalidation/mint storms across client factories.
type tokenRefreshCoordinator struct {
	mu       sync.Mutex
	inflight map[string]*refreshEntry
}

type refreshEntry struct {
	done  chan struct{}
	token string
	err   error
}

func newTokenRefreshCoordinator() *tokenRefreshCoordinator {
	return &tokenRefreshCoordinator{
		inflight: make(map[string]*refreshEntry),
	}
}

// Refresh executes fn at most once per key for concurrent callers. If a refresh
// for the same key is already in-flight, callers wait for its result (or return
// early if their context is canceled).
func (c *tokenRefreshCoordinator) Refresh(ctx context.Context, key string, fn tokenRefreshFunc) (string, error) {
	c.mu.Lock()
	if entry, ok := c.inflight[key]; ok {
		c.mu.Unlock()
		select {
		case <-entry.done:
			return entry.token, entry.err
		case <-ctx.Done():
			return "", ctx.Err()
		}
	}

	entry := &refreshEntry{done: make(chan struct{})}
	c.inflight[key] = entry
	c.mu.Unlock()

	// Ensure cleanup even if fn panics.
	defer func() {
		close(entry.done)
		c.mu.Lock()
		delete(c.inflight, key)
		c.mu.Unlock()
	}()

	token, err := fn(ctx)
	entry.token = token
	entry.err = err

	return token, err
}
