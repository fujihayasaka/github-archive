package reporter

import (
	"context"
	"fmt"
	"os"
	"testing"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-exceptions"
	"github.com/github/go-exceptions/exporters/writer"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func Test_Reporter(t *testing.T) {
	ctx := context.Background()

	t.Run("null reporter", func(t *testing.T) {
		assert.Equal(t, exceptions.NullReporter, GetBaseReporter())
		Report(ctx, fmt.Errorf("test"), kvp.String("test", "test"))
	})

	t.Run("global reporter", func(t *testing.T) {
		baseReporter, err := exceptions.NewReporter(
			exceptions.WithApplication("noop"),
			exceptions.WithExporter(writer.NewExporter(os.Stdout)),
		)
		require.NoError(t, err)

		SetReporter(baseReporter)

		assert.Equal(t, baseReporter, GetBaseReporter())
		Report(ctx, fmt.Errorf("test"), kvp.String("test", "test"))
	})
}
