package tester

import (
	"sync"
	"time"

	"github.com/pkg/errors"
)

var (
	errorTestTimeout     = errors.New("test execution exceeded timeout")
	requestRetryTime     = 40 * time.Millisecond
	dotcomMaxTries       = 3
	authndMaxTries       = 6
	dotcomTriesExhausted = errors.New("max tries exhausted attempting request to dotcom")
	authndTriesExhausted = errors.New("max tries exhausted attempting request to authnd")
)

// runTracker tracks runs of a particular test that are in progress
type runTracker interface {
	Start()
	Stop()
	IsRunning() bool
}

// singleRunTracker tracks runs of a test where only one instance is allowed to
// be running at a given time.
type singleRunTracker struct {
	mu      sync.RWMutex
	running bool
}

func (t *singleRunTracker) Start() {
	t.mu.Lock()
	t.running = true
	t.mu.Unlock()
}

func (t *singleRunTracker) Stop() {
	t.mu.Lock()
	t.running = false
	t.mu.Unlock()
}

func (t *singleRunTracker) IsRunning() bool {
	t.mu.RLock()
	defer t.mu.RUnlock()
	return t.running
}
