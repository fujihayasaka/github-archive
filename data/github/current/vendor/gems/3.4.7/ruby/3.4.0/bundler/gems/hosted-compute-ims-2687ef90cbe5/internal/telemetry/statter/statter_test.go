package statter

import (
	"context"
	"io"
	"testing"
	"time"

	"github.com/github/go-stats"
	"github.com/stretchr/testify/assert"
)

func Test_Statter(t *testing.T) {
	ctx := context.Background()

	t.Run("null logger", func(t *testing.T) {
		assert.Equal(t, stats.NullStatter, GetBaseStatter())
		Counter(ctx, "test", 1)
	})

	t.Run("global logger", func(t *testing.T) {
		baseStatter := stats.NewClient(io.Discard, 5*time.Second, "test")
		baseStatter.Run()
		defer baseStatter.Stop()

		SetStatter(baseStatter)

		assert.Equal(t, baseStatter, GetBaseStatter())
		Counter(ctx, "test", 1)
	})
}
