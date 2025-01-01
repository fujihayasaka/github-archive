package azp

import (
	"context"
	"testing"
	"time"

	"github.com/github/launch/observability"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestBufferedTenantKeyGenerator_InstantWhenPopulated(t *testing.T) {
	// buffer size is greater than number of requests
	buffer := NewBufferedTenantKeyGenerator(3, 1, observability.NewNullObservability())
	waitUntilFull(buffer)

	duration := timeMethod(func() {
		// read from buffer
		key, err := buffer.Get(context.Background())
		require.NoError(t, err)
		assert.NotNil(t, key)
		// read from buffer
		key, err = buffer.Get(context.Background())
		require.NoError(t, err)
		assert.NotNil(t, key)
	})
	assert.True(t, duration.Milliseconds() < 10)
}

func TestBufferedTenantKeyGenerator_SlowerWhenNotPopulated(t *testing.T) {
	// buffer size is smaller than number of requests
	buffer := NewBufferedTenantKeyGenerator(1, 1, observability.NewNullObservability())
	waitUntilFull(buffer)

	duration := timeMethod(func() {
		// read from buffer
		key, err := buffer.Get(context.Background())
		require.NoError(t, err)
		assert.NotNil(t, key)
		// not read from buffer, so should take time
		key, err = buffer.Get(context.Background())
		require.NoError(t, err)
		assert.NotNil(t, key)
	})
	assert.True(t, duration.Milliseconds() > 10)
}

func TestBufferedTenantKeyGenerator_AvoidsBlockingWhenBufferEmpty(t *testing.T) {
	// 0 workers, buffer will never be populated
	buffer := NewBufferedTenantKeyGenerator(1, 0, observability.NewNullObservability())

	key, err := buffer.Get(context.Background())
	require.NoError(t, err)
	assert.NotNil(t, key)
}

func TestBufferedTenantKeyGenerator_RespectsContextTimeout(t *testing.T) {
	// buffer size is smaller than number of requests
	buffer := NewBufferedTenantKeyGenerator(1, 1, observability.NewNullObservability())
	waitUntilFull(buffer)

	// read from buffer
	key, err := buffer.Get(context.Background())
	require.NoError(t, err)
	assert.NotNil(t, key)

	// create a context with a timeout shorter than generating a key can ever take
	ctx, cancel := context.WithTimeout(context.Background(), time.Nanosecond)
	defer cancel()
	// not read from buffer, so should take time
	_, err = buffer.Get(ctx)
	assert.Error(t, err)
}

func waitUntilFull(generator TenantKeyGenerator) {
	// wait for buffer to be full
	for generator.CurrentSize() != generator.MaxSize() {
		time.Sleep(time.Millisecond * 100)
	}
}

func timeMethod(callback func()) time.Duration {
	b := time.Now()
	callback()
	return time.Now().Sub(b)
}
