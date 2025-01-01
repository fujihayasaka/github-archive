package testutils

import (
	"context"
	"errors"
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestRecordingLogger(t *testing.T) {
	ctx := context.Background()
	rl := NewRecordingLogger()
	rl.Logger.Error(ctx, "boom")
	assert.Contains(t, rl.String(), "boom")

	rl.Logger.Report(ctx, errors.New("thing failed"))
	assert.Contains(t, rl.String(), "thing failed")
	assert.Contains(t, rl.String(), "boom")
}
