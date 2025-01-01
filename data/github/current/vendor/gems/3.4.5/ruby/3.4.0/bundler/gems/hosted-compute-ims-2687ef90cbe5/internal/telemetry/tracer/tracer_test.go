package tracer

import (
	"context"
	"testing"

	"github.com/stretchr/testify/assert"
	"go.opentelemetry.io/otel"
)

func Test_Tracer(t *testing.T) {
	ctx := context.Background()

	t.Run("null logger", func(t *testing.T) {
		assert.Equal(t, otel.Tracer("hosted-compute-ims"), GetTracer())
		_, span := StartSpan(ctx, "test")
		span.End()
	})

	t.Run("global logger", func(t *testing.T) {
		baseTracer := otel.Tracer("noop")

		SetTracer(baseTracer)

		assert.Equal(t, baseTracer, GetTracer())
		_, span := StartSpan(ctx, "test")
		span.End()
	})
}
