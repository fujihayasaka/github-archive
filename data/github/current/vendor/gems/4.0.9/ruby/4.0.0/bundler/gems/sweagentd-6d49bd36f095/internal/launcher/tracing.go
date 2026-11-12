package launcher

import (
	"context"

	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/traceparent"
	"go.opentelemetry.io/otel/trace"
)

// getCopilotTraceParent creates a new "Job Execution" span and extracts a signed traceparent from it.
// This groups all job traces under a single parent span.
// It returns an empty string if the feature flag is not enabled or if there is no active span.
func getCopilotTraceParent(ctx context.Context, client featureflags.Client, launchAgentOpts *LaunchAgentOpts, propagator traceparent.Propagator) string {
	if !client.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEPropagateTraceParent, launchAgentOpts) {
		return ""
	}

	if propagator == nil {
		return ""
	}

	span := trace.SpanFromContext(ctx)
	if !span.SpanContext().IsValid() {
		return ""
	}

	// Create a new "Job Execution" span to group all job traces under it
	tracer := span.TracerProvider().Tracer("sweagentd")
	_, jobSpan := tracer.Start(ctx, "Job Execution")
	defer jobSpan.End()

	// Use the propagator to get signed traceparent from the new span
	spanCtx := trace.ContextWithSpan(ctx, jobSpan)
	traceParent, _ := propagator.GetCopilotTraceparent(spanCtx)

	return traceParent
}
