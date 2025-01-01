package retry

import (
	"context"
	"testing"
	"time"

	"github.com/cenkalti/backoff/v4"
	"github.com/github/github-telemetry-go/log"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestRetry(t *testing.T) {
	var attempts int
	fn := func() error {
		attempts++
		return assert.AnError
	}
	policy := backoff.NewExponentialBackOff(backoff.WithMaxElapsedTime(1 * time.Second))
	err := Retry(fn, backoff.WithContext(policy, context.Background()), log.NewNullLogger())
	require.ErrorIs(t, err, assert.AnError)
	assert.Greater(t, attempts, 1)
}
