package rate

import (
	"context"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
)

func TestGHESRateLimiter(t *testing.T) {
	ctx := context.Background()
	if testing.Short() {
		t.Skip("skipping test in short mode.")
	}

	limiter := NewGHESRateLimiter(1)
	first := limiter.Allow(ctx, 0)
	assert.True(t, first, "First request should be allowed")

	time.Sleep(100 * time.Millisecond)

	second := limiter.Allow(ctx, 0)
	assert.False(t, second, "Second request should not be allowed")

	time.Sleep(60 * time.Second)

	third := limiter.Allow(ctx, 0)
	assert.True(t, third, "Third request should be allowed after 60 seconds")
}
