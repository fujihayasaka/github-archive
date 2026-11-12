package launcher

import (
	"context"

	"github.com/github/sweagentd/internal/agenticapp"
	"github.com/github/sweagentd/internal/featureflags"
)

const (
	copilotRuntimeSlugCCA    = "cca"
	copilotRuntimeSlugCCAV3  = "cca-v3"
	copilotRuntimeSlugClaude = "claude"
	copilotRuntimeSlugCodex  = "codex"
	copilotRuntimeEntrypoint = "dist/index.js"
	ccaRuntimeEntrypoint     = "dist-cca/index.js"
	ccaV3RuntimeEntrypoint   = "dist-cca-v3/index.js"
	claudeRuntimeEntrypoint  = "dist-claude/index.js"
	codexRuntimeEntrypoint   = "dist-codex/index.js"
)

// analysisEventTypes lists event types that require the default runtime entry
// point (dist/index.js) because only that entry point implements analysis task
// handling (emitNamespacedProgress for ci-analysis findings). Alternate runtimes
// like CCA v3 do not support these event types yet.
// TODO: Remove this bypass once analysis handling is extracted into a shared
// module used by all entry points. See https://github.com/github/copilot-code-review/issues/2337
//
// Note: These mirror the constants in internal/jobs/job.go but are duplicated
// here to avoid an import cycle (jobs already imports launcher).
var analysisEventTypes = map[string]bool{
	"ci_failure_analysis":            true,
	"ci_check_run_failure_analysis":  true,
	"verification_platform_findings": true,
}

type runtimeSelection struct {
	entryPoint  string
	releaseSlug string
	setup       string
}

func usesCopilotRuntimeVariants(opts *LaunchAgentOpts) bool {
	return opts.Agent.ComputeSlug() == agenticapp.CopilotComputeSlug || opts.Agent.IsThirdPartyApp()
}

// isAnalysisEventType returns true if the job event type requires the default
// runtime entry point for analysis task handling.
func isAnalysisEventType(eventType string) bool {
	return analysisEventTypes[eventType]
}

func selectRuntime(ctx context.Context, ffClient featureflags.Client, opts *LaunchAgentOpts) runtimeSelection {
	releaseSlug := opts.Agent.EngineSlug()
	if opts.Agent.IsThirdPartyApp() {
		releaseSlug = agenticapp.CopilotComputeSlug
	}
	selection := runtimeSelection{
		entryPoint:  copilotRuntimeEntrypoint,
		releaseSlug: releaseSlug,
	}
	if ffClient == nil || !usesCopilotRuntimeVariants(opts) {
		return selection
	}

	// Analysis event types (CI failure analysis, verification platform findings)
	// require the default runtime entry point which has the necessary
	// emitNamespacedProgress support. Skip variant selection for these jobs.
	if isAnalysisEventType(opts.JobEventType) {
		return selection
	}

	if ffClient.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgentRuntimeEntryPointCCAV3App, opts) &&
		!ffClient.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgentRuntimeEntryPointCCAV3AppOptOut, opts) {
		selection.entryPoint = ccaV3RuntimeEntrypoint
		selection.releaseSlug = copilotRuntimeSlugCCAV3
		return selection
	}

	// Third-party apps use Copilot runtime assets, but only the CCA v3 flag should
	// alter their runtime variant.
	if opts.Agent.IsThirdPartyApp() {
		return selection
	}

	if ffClient.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgentRuntimeEntryPointCCAV2, opts) {
		selection.entryPoint = ccaRuntimeEntrypoint
		selection.releaseSlug = copilotRuntimeSlugCCA
		return selection
	}

	if ffClient.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgentRuntimeEntryPointClaude, opts) {
		selection.entryPoint = claudeRuntimeEntrypoint
		selection.releaseSlug = copilotRuntimeSlugClaude
		return selection
	}

	if ffClient.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgentRuntimeEntryPointCodex, opts) {
		selection.entryPoint = codexRuntimeEntrypoint
		selection.releaseSlug = copilotRuntimeSlugCodex
		selection.setup = agenticapp.CodexSetupCommand
		return selection
	}

	return selection
}
