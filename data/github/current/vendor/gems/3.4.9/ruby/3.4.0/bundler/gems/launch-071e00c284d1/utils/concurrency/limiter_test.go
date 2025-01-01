package concurrency

import (
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
)

func TestNewLimiter(t *testing.T) {
	l := NewLimiter(3)

	wg := sync.WaitGroup{}
	wg.Add(1)
	started := int64(0)

	go (func() {
		for i := 0; i < 5; i++ {
			l.Check()
			go (func() {
				atomic.AddInt64(&started, 1)
				defer l.Done()
				wg.Wait()
			})()
		}
	})()

	// make sure the go routines have a chance to run
	time.Sleep(35 * time.Millisecond)

	assert.Equal(t, atomic.LoadInt64(&started), int64(3))
	wg.Done()

	time.Sleep(35 * time.Millisecond)
	assert.Equal(t, atomic.LoadInt64(&started), int64(5))
}
