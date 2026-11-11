package launcher

import (
	"context"
	"encoding/hex"
	"unicode/utf8"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/sweagentd/internal/observability"
)

// workflowContentDebugLogMaxBytes caps the size of workflow content included in
// the debug log to bound log volume. The monolith yaml size limit is ~64KB, so
// 32KB captures most of any realistic payload while keeping log records reasonable.
const workflowContentDebugLogMaxBytes = 32 * 1024

// prepareWorkflowContentForDebugLog truncates the workflow content to
// workflowContentDebugLogMaxBytes and hex-encodes it if it is not valid UTF-8.
// Hex encoding is required for invalid bytes because the log pipeline would
// otherwise fail to emit the record with the same encoding error we are
// debugging.
func prepareWorkflowContentForDebugLog(content string) (encoded string, validUTF8, truncated bool) {
	if len(content) > workflowContentDebugLogMaxBytes {
		content = content[:workflowContentDebugLogMaxBytes]
		truncated = true
	}
	validUTF8 = utf8.ValidString(content)
	if validUTF8 {
		encoded = content
	} else {
		encoded = hex.EncodeToString([]byte(content))
	}
	return encoded, validUTF8, truncated
}

// logWorkflowContentForDebugging emits a single structured log with the generated
// workflow yaml that failed to dispatch, for debugging monolith-side errors such
// as Encoding::UndefinedConversionError (availability-incident-4338).
//
// The caller is responsible for gating this on the
// CopilotSWEAgentLogInvalidUTF8Workflow feature flag; this function itself does
// not re-check the flag.
func logWorkflowContentForDebugging(
	ctx context.Context,
	obsv observability.Exporters,
	workflowContent string,
	customSetupStepsUsed bool,
	dispatchErr error,
) {
	encoded, valid, truncated := prepareWorkflowContentForDebugLog(workflowContent)
	encoding := "utf8"
	if !valid {
		encoding = "hex"
	}

	obsv.LoggerWithTelemetry(ctx).Warn("Dispatching dynamic workflow failed; logging generated workflow content for debugging",
		kvp.Int("workflow_content_length", len(workflowContent)),
		kvp.Bool("workflow_content_truncated", truncated),
		kvp.Bool("workflow_content_valid_utf8", valid),
		kvp.String("workflow_content_encoding", encoding),
		kvp.String("workflow_content", encoded),
		kvp.Bool("custom_setup_steps_used", customSetupStepsUsed),
		kvp.String("dispatch_error", dispatchErr.Error()),
	)
}
