package azp

import (
	"context"
	"crypto/rand"
	"crypto/rsa"
	"strconv"
	"time"

	"github.com/github/launch/observability"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/observability/tracing"
)

const (
	repoKeyBitSize = 4096
)

// TenantKeyGenerator exists to create and store RSA private keys for tenant creation
// Creating a key can be a slow operation (many seconds) so instead we keep a
// channel populated with keys so there should always be some ready and waiting.
type TenantKeyGenerator interface {
	Get(ctx context.Context) (*rsa.PrivateKey, error)
	CurrentSize() int
	MaxSize() int
}

type bufferedTenantKeyGenerator struct {
	obs     *observability.Observability
	maxSize int
	// the channel itself
	buf chan *rsa.PrivateKey
}

// The correct bufferSize should be picked to deal with a few requests over a
// short period of time.
func NewBufferedTenantKeyGenerator(bufferSize, workers int, obs *observability.Observability) TenantKeyGenerator {
	c := &bufferedTenantKeyGenerator{
		obs:     obs,
		maxSize: bufferSize,
		// create a buffered channel
		buf: make(chan *rsa.PrivateKey, bufferSize),
	}
	// create multiple goroutines to push keys onto the queue.
	// one seems to be enough but having this be configurable may be useful
	// on GHES or in the future if workloads change dramatically.
	for i := 0; i < workers; i++ {
		go func() {
			for {
				// create a key
				start := time.Now()
				key, err := rsa.GenerateKey(rand.Reader, repoKeyBitSize)
				if err != nil {
					// report the error and sleep
					obs.Report(context.Background(), err)
					time.Sleep(100 * time.Millisecond)
				} else {
					c.obs.Timing(context.Background(), "generate_tenant_key", nil, time.Since(start))
					// push it to the channel.
					// this is a blocking operation if the channel is full.
					c.buf <- key
				}
			}
		}()
	}

	obs.Periodically(func(stats statter.Statter) {
		stats.Gauge(context.Background(), "tenant_key_buffer_length", nil, int64(c.CurrentSize()))
	})
	return c
}

func (c *bufferedTenantKeyGenerator) MaxSize() int {
	return c.maxSize
}

func (c *bufferedTenantKeyGenerator) CurrentSize() int {
	return len(c.buf)
}

func (c *bufferedTenantKeyGenerator) Get(ctx context.Context) (*rsa.PrivateKey, error) {
	// tracing for performance analysis.
	ctx, span := tracing.Start(ctx)
	defer span.End()

	var buffered, timeout bool
	start := time.Now()
	defer func() {
		c.obs.Timing(ctx, "get_tenant_key", statter.Tags{
			"buffered": strconv.FormatBool(buffered),
			"timeout":  strconv.FormatBool(timeout),
		}, time.Since(start))
	}()

	// if the channel is empty, generate a key in the current goroutine.
	// this will be slow, but it avoids multiple callers all waiting
	// on a small set of workers to generate keys and populate the buffer.
	select {
	case key := <-c.buf:
		buffered = true
		return key, nil
	case <-ctx.Done():
		timeout = true
		c.obs.Counter(ctx, "tenant_key_buffer_request_timeout", statter.Tags{}, 1)
		return nil, ctx.Err()
	default:
		return rsa.GenerateKey(rand.Reader, repoKeyBitSize)
	}
}
