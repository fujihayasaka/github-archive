package logger

import (
	"context"
	"testing"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func Test_Logger(t *testing.T) {
	ctx := context.Background()

	t.Run("null logger", func(t *testing.T) {
		assert.Equal(t, log.NewNullLogger(), GetBaseLogger())
		Info(ctx, "test", kvp.String("test", "test"))
	})

	t.Run("global logger", func(t *testing.T) {
		baseLogger, err := log.NewFromEnv()
		require.NoError(t, err)

		SetLogger(baseLogger)

		assert.Equal(t, baseLogger, GetBaseLogger())
		Info(ctx, "test", kvp.String("test", "test"))
	})
}
