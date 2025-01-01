package shutdown

import (
	"context"
	"errors"
	"sync"
	"syscall"
	"testing"
	"time"

	"github.com/github/github-telemetry-go/log"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// counter is a helper type to assert cleanup functions are called
type counter struct {
	count int
	mu    sync.RWMutex
}

func (c *counter) inc() {
	c.mu.Lock()
	c.count++
	c.mu.Unlock()
}

func (c *counter) counter() int {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.count
}

func (c *counter) called() bool {
	return c.counter() == 1
}

var tests = []struct {
	name   string
	signal syscall.Signal
}{
	{
		name:   "SIGINT",
		signal: syscall.SIGINT,
	},
	{
		name:   "SIGTERM",
		signal: syscall.SIGTERM,
	},
}

func TestShutdownNoError(t *testing.T) {
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			counter := new(counter)
			sd := New(1*time.Millisecond, log.NewNullLogger())
			sd.Register(func(context.Context) error {
				counter.inc()
				return nil
			})
			go func() {
				err := sd.Wait(context.Background())
				assert.NoError(t, err)
			}()
			time.Sleep(1 * time.Millisecond)
			err := syscall.Kill(syscall.Getpid(), tc.signal)
			require.NoError(t, err)
			require.Eventually(t, counter.called, 10*time.Millisecond, 1*time.Millisecond, "cleanup function not called")
		})
	}
}

func TestShutdownError(t *testing.T) {
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			counter := new(counter)
			sd := New(1*time.Millisecond, log.NewNullLogger())
			sd.Register(func(context.Context) error {
				counter.inc()
				return errors.New("")
			})
			go func() {
				err := sd.Wait(context.Background())
				assert.Error(t, err)
			}()
			time.Sleep(1 * time.Millisecond)
			err := syscall.Kill(syscall.Getpid(), tc.signal)
			require.NoError(t, err)
			require.Eventually(t, counter.called, 10*time.Millisecond, 1*time.Millisecond, "cleanup function not called")
		})
	}
}

func TestShutdownTimeout(t *testing.T) {
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			counter := new(counter)
			sd := New(1*time.Millisecond, log.NewNullLogger())
			sd.Register(func(ctx context.Context) error {
				<-ctx.Done()
				counter.inc()
				return errors.New("")
			})
			go func() {
				err := sd.Wait(context.Background())
				assert.Error(t, err)
			}()
			time.Sleep(1 * time.Millisecond)
			err := syscall.Kill(syscall.Getpid(), tc.signal)
			require.NoError(t, err)
			require.Eventually(t, counter.called, 10*time.Millisecond, 1*time.Millisecond, "cleanup function not called")
		})
	}
}

func TestShutdownMultipleCleanups(t *testing.T) {
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			counter := new(counter)
			sd := New(1*time.Millisecond, log.NewNullLogger())
			for range 10 {
				sd.Register(func(context.Context) error {
					counter.inc()
					return nil
				})
			}
			go func() {
				err := sd.Wait(context.Background())
				assert.NoError(t, err)
			}()
			time.Sleep(1 * time.Millisecond)
			err := syscall.Kill(syscall.Getpid(), tc.signal)
			require.NoError(t, err)
			require.Eventually(t, func() bool { return counter.counter() == 10 }, 10*time.Millisecond, 1*time.Millisecond, "cleanup function not called")
		})
	}
}

func TestWrapNoContext(t *testing.T) {
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			counter := new(counter)
			sd := New(1*time.Millisecond, log.NewNullLogger())
			sd.Register(WrapNoContext(func() error {
				counter.inc()
				return nil
			}))
			go func() {
				err := sd.Wait(context.Background())
				assert.NoError(t, err)
			}()
			time.Sleep(1 * time.Millisecond)
			err := syscall.Kill(syscall.Getpid(), tc.signal)
			require.NoError(t, err)
			require.Eventually(t, counter.called, 10*time.Millisecond, 1*time.Millisecond, "cleanup function not called")
		})
	}
}

func TestWrapNoContextTimeout(t *testing.T) {
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			counter := new(counter)
			sd := New(1*time.Millisecond, log.NewNullLogger())
			sd.Register(WrapNoContext(func() error {
				time.Sleep(2 * time.Millisecond)
				counter.inc()
				return nil
			}))
			go func() {
				err := sd.Wait(context.Background())
				assert.Error(t, err)
			}()
			time.Sleep(1 * time.Millisecond)
			err := syscall.Kill(syscall.Getpid(), tc.signal)
			require.NoError(t, err)
			require.Eventually(t, counter.called, 10*time.Millisecond, 1*time.Millisecond, "cleanup function not called")
		})
	}
}

func TestWrapNoError(t *testing.T) {
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			counter := new(counter)
			sd := New(1*time.Millisecond, log.NewNullLogger())
			sd.Register(WrapNoError(func(context.Context) { counter.inc() }))
			go func() {
				err := sd.Wait(context.Background())
				assert.NoError(t, err)
			}()
			time.Sleep(1 * time.Millisecond)
			err := syscall.Kill(syscall.Getpid(), tc.signal)
			require.NoError(t, err)
			require.Eventually(t, counter.called, 10*time.Millisecond, 1*time.Millisecond, "cleanup function not called")
		})
	}
}

func TestWrapNoErrorAndContext(t *testing.T) {
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			counter := new(counter)
			sd := New(1*time.Millisecond, log.NewNullLogger())
			sd.Register(WrapNoErrorAndContext(counter.inc))
			go func() {
				err := sd.Wait(context.Background())
				assert.NoError(t, err)
			}()
			time.Sleep(1 * time.Millisecond)
			err := syscall.Kill(syscall.Getpid(), tc.signal)
			require.NoError(t, err)
			require.Eventually(t, counter.called, 10*time.Millisecond, 1*time.Millisecond, "cleanup function not called")
		})
	}
}

func TestWrapNoErrorAndContextTimeout(t *testing.T) {
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			counter := new(counter)
			sd := New(1*time.Millisecond, log.NewNullLogger())
			sd.Register(WrapNoErrorAndContext(func() {
				time.Sleep(2 * time.Millisecond)
				counter.inc()
			}))
			go func() {
				err := sd.Wait(context.Background())
				assert.Error(t, err)
			}()
			time.Sleep(1 * time.Millisecond)
			err := syscall.Kill(syscall.Getpid(), tc.signal)
			require.NoError(t, err)
			require.Eventually(t, counter.called, 10*time.Millisecond, 1*time.Millisecond, "cleanup function not called")
		})
	}
}
