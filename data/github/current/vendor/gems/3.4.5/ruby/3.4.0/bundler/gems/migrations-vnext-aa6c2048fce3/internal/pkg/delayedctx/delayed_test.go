package delayedctx

import (
	"context"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
)

func TestContext(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	delayedCtx, delayedCancel := WithDelayedCancelContext(ctx, 3*time.Second)
	defer delayedCancel()

	now := time.Now()
	cancel()
	<-delayedCtx.Done()
	assert.WithinDuration(t, now.Add(3*time.Second), time.Now(), 1*time.Second)
}
