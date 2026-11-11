package jobservice

import (
	"context"
	"errors"
	"fmt"
	"slices"
	"strings"

	copilotUsersTwirp "github.com/github/copilot-twirp/proto/users/v1"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	"github.com/github/sweagentd/internal/capi"
	"github.com/github/sweagentd/internal/experiments/exp"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/sweagentd"
)

var (
	// ErrModelNotFound is returned when the requested model is not found or not enabled for the user.
	ErrModelNotFound = errors.New("model not found or not enabled for user")
	// ErrNoModelAvailable is returned when no coding-agent-capable models are available for the user (due to policies or feature flags).
	ErrNoModelAvailable = errors.New("no model available for user")
	// ErrModelVendorMismatch is returned when the requested model belongs to a different vendor than the agent requires.
	ErrModelVendorMismatch = errors.New("model vendor does not match agent")
)

func newErrModelNotFound() error {
	return goerrors.WithStackOffset(ErrModelNotFound, 1)
}

func newErrNoModelAvailable() error {
	return goerrors.WithStackOffset(ErrNoModelAvailable, 1)
}

// checkVendorMismatch returns ErrModelVendorMismatch when the user explicitly
// requested a model that exists in allModels but was filtered out by the
// vendor restriction. Returns nil when no mismatch is detected (caller should
// fall through to the original error).
func checkVendorMismatch(requestedModel, agentName string, vendors []string, allModels []capi.Model) error {
	if requestedModel == "" || requestedModel == capi.AutoMode || len(allModels) == 0 {
		return nil
	}
	modelID := strings.TrimPrefix(requestedModel, jobs.CapiModelPrefix)
	if userCanAccessModel(modelID, allModels) {
		return goerrors.Errorf("model %q is not compatible with %s (requires %s vendor): %w",
			modelID, agentName, strings.Join(vendors, ", "), ErrModelVendorMismatch)
	}
	return nil
}

// stripModelPrefix removes the CAPI prefix from a model name if present.
// This is used when sending model information to external services (like the session service)
// that should not be exposed to this implementation detail.
func stripModelPrefix(model string) string {
	return strings.TrimPrefix(model, jobs.CapiModelPrefix)
}

// ExperimentalModel1 is the model that is used by the agent when the `ModelCompareExperiment` variant returns 1.
// const ExperimentalModel1 = jobs.CapiModelPrefix + "claude-opus-4.5"

// ExperimentalModel2 is the model that is used by the agent when the `ModelCompareExperiment` variant returns 2.
// const ExperimentalModel2 = "sweagent-capi:oswe-prime"

// ExperimentalModels is a map of experimental models that can be used by the ModelCompareExperiment.
var ExperimentalModels = map[int]string{
	// 1: ExperimentalModel1,
	// 2: ExperimentalModel2,
}

// AutoModelExperimentModels maps experiment variant keys to models for auto
// model selection. The keys correspond to treatment keys in
// exp.CopilotCodingAgentAutoModel (e.g. "var1", "var2").
var AutoModelExperimentModels = map[string]string{
	"var1": capi.GPT53Codex,
	"var2": capi.ClaudeOpus46,
}

// AutoModels is the default list of models that can be selected when "auto" mode is enabled.
// The order of this list matters, as the first model that the user has access to will be selected.
var AutoModels = []string{
	capi.ClaudeSonnet46,
}

// AutoModelsExpanded is the expanded list of models for auto mode, gated by the
// CodingAgentAutoModelExpanded feature flag.
//
// These models MUST be 1x models.
var AutoModelsExpanded = []string{
	capi.ClaudeSonnet46,
	capi.ClaudeSonnet45,
	capi.GPT54,
	capi.GPT53Codex,
	capi.GPT52Codex,
}

// FallbackAutoModel is the model that is used when no other models are available in auto mode.
// GPT-5.3-Codex is the long-term supported (LTS) base model guaranteed to be available for all
// Copilot Business and Enterprise customers, making it the safe choice as a last-resort fallback.
var FallbackAutoModel = capi.GPT53Codex

// DetermineModel determines the model to use when the agent is launched based on the feature flags
// and experiments that are enabled for the actor, repo or repo owner.
// The agentID parameter identifies which agentic app is being used; for third-party agents,
// model selection is restricted to models from that agent's vendor.
func (s *Service) DetermineModel(ctx context.Context, requestedModel string, job *jobs.Job, agentID int64, userDetails *copilotUsersTwirp.CopilotUserDetails) (string, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "jobservice.DetermineModel")
	defer span.End()
	logger := s.obsv.LoggerWithTelemetry(ctx)

	// Look up the agent first so we can check for model passthrough before
	// making any network calls (e.g. CAPI model list).
	agent, agentErr := s.appProvider.FindByID(ctx, agentID)
	if agentErr != nil {
		return "", goerrors.Errorf("finding agent: %w", agentErr)
	}

	// If the agent manages its own model selection (e.g. Copilot Code Review)
	// and a model was explicitly requested, pass it through without validation.
	// This is safe because CreateJob is HMAC-authenticated (only trusted callers
	// can reach this path) and the agentID must map to a registered AgenticApp
	// that explicitly implements AgenticAppModelPassthrough to opt in.
	if requestedModel != "" {
		if mp, ok := agent.(sweagentd.AgenticAppModelPassthrough); ok && mp.SkipModelValidation() {
			logger.Info("model passthrough: skipping validation for agent-managed model",
				kvp.String("model", requestedModel),
				kvp.Int64("agent_id", agentID),
			)
			job.IsAutoMode = false
			return requestedModel, nil
		}
	}

	// Use the agent's CAPI integration ID (if set) so that CAPI can
	// identify the specific agent integration (e.g. claude-code-cloud,
	// codex-cloud) on /models calls.
	if s.ffs.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CodingAgentCAPI3pIntegrationID, job) {
		if integrationID := agent.Metadata()[sweagentd.MetadataCAPIIntegrationID]; integrationID != "" {
			ctx = capi.ContextWithCAPIIntegrationID(ctx, integrationID)
		}
	}

	// Get a list of models the actor (user or org) is allowed to use. We need this list to
	// validate which models the actor can select from, or to choose from in auto mode.
	allModels, err := s.capi.ListCodingAgentModels(ctx, uint64(job.ActorID), string(job.ActorType))
	if err != nil {
		return "", goerrors.Errorf("listing models: %w", err)
	}

	models := allModels
	if vendors := agent.ModelVendors(); len(vendors) > 0 && s.ffs.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CodingAgentThirdPartyModelVendorFilter, job) {
		models = filterModelsByVendors(models, vendors)
		logger.Info("filtered models by vendor for third-party agent",
			kvp.String("vendors", strings.Join(vendors, ",")),
			kvp.Int("model_count", len(models)),
		)
	}

	// The actor doesn't have any coding-agent models available, likely because
	// their Copilot license has all of the model policies disabled.
	if len(models) == 0 {
		// If vendor filtering removed all models and the user explicitly requested a
		// model that exists in the unfiltered list, report a vendor mismatch instead
		// of a generic "no models available" error.
		mismatchErr := checkVendorMismatch(requestedModel, agent.AppName(), agent.ModelVendors(), allModels)
		if mismatchErr != nil {
			logger.Warn("model vendor mismatch: requested model does not match agent vendor",
				kvp.String("model", strings.TrimPrefix(requestedModel, jobs.CapiModelPrefix)),
				kvp.String("agent", agent.AppName()),
				kvp.String("vendors", strings.Join(agent.ModelVendors(), ",")),
			)
			return "", mismatchErr
		}
		// For first-party agents (no vendor restriction), fall back to the LTS base model
		// (GPT-5.3-Codex) when all models are unavailable due to policy restrictions.
		// This ensures users can still start agent tasks even if their preferred models
		// are disabled by enterprise admin policies.
		if len(agent.ModelVendors()) == 0 {
			logger.Info("no models available for user, falling back to guaranteed base model",
				kvp.String("fallback_model", FallbackAutoModel))
			job.IsAutoMode = false
			return jobs.CapiModelPrefix + FallbackAutoModel, nil
		}
		logger.Info("no models available for user")
		return "", newErrNoModelAvailable()
	}

	// Default to "auto" if no model is specified
	if requestedModel == "" {
		requestedModel = capi.AutoMode
	}

	if userDetails == nil {
		logger.Error("failed to get Copilot user details for user, using default model", kvp.String("model", capi.ClaudeSonnet45))
		return "", goerrors.New("getting copilot user details")
	}

	plan, err := githubtwirp.CopilotPlanFromUser(userDetails)
	if err != nil {
		logger.WithError(err).Error("failed to get Copilot plan for user, using default model", kvp.String("model", capi.ClaudeSonnet45))
		return "", goerrors.Errorf("determining copilot user plan: %w", err)
	}

	useAuto := requestedModel == capi.AutoMode || s.mustUseAutoModel(ctx, plan, job)
	logger = logger.WithFields(kvp.Bool("auto_mode", useAuto), kvp.String("requested_model", requestedModel))
	logger.Info("determining model to use")

	// Validate the requested model before using it as a tag. We need to do this because the requestedModel is a user-provided
	// value, and we don't want to have unbounded cardinality in our metrics. The provided value is still logged above.
	requestedModelTag := "other"
	if useAuto {
		requestedModelTag = "auto"
	} else if !strings.Contains(requestedModel, ":") && slices.Contains(capi.CodingAgentModelIDs(), requestedModel) {
		requestedModelTag = requestedModel
	}
	s.obsv.Increment(ctx, "jobservice.model_requested", stats.Tags{"model": requestedModelTag})

	// Only pass the vendors to determineModel when the vendor filter flag is enabled.
	// This ensures the auto model path also respects the flag.
	var vendorsForModel []string
	if len(agent.ModelVendors()) > 0 && s.ffs.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CodingAgentThirdPartyModelVendorFilter, job) {
		vendorsForModel = agent.ModelVendors()
	}

	model, err := s.determineModel(ctx, requestedModel, models, userDetails, plan, job, useAuto, vendorsForModel)
	if err != nil {
		// If the model was not found or no models are available and vendor filtering is active,
		// check if this is a vendor mismatch (the model exists but belongs to a different vendor).
		if len(vendorsForModel) > 0 &&
			(errors.Is(err, ErrModelNotFound) || errors.Is(err, ErrNoModelAvailable)) {
			mismatchErr := checkVendorMismatch(requestedModel, agent.AppName(), vendorsForModel, allModels)
			if mismatchErr != nil {
				logger.Warn("model vendor mismatch: requested model does not match agent vendor",
					kvp.String("model", strings.TrimPrefix(requestedModel, jobs.CapiModelPrefix)),
					kvp.String("agent", agent.AppName()),
					kvp.String("vendors", strings.Join(vendorsForModel, ",")),
				)
				return "", mismatchErr
			}
		}
		return "", goerrors.Errorf("determining model: %w", err)
	}

	job.IsAutoMode = useAuto

	logger.Info("determined model", kvp.String("model", model))
	s.obsv.Increment(ctx, "jobservice.model_determined", stats.Tags{"auto": fmt.Sprintf("%t", useAuto), "model": model})
	return model, nil
}

func (s *Service) determineModel(ctx context.Context, requestedModel string, models []capi.Model, userDetails *copilotUsersTwirp.CopilotUserDetails, plan githubtwirp.CopilotPlan, job *jobs.Job, useAuto bool, modelVendors []string) (string, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "jobservice.determineModel")
	defer span.End()

	if useAuto {
		model, err := s.useAutoModel(ctx, models, userDetails, plan, job, modelVendors)
		if err != nil {
			return "", err
		}

		// Prepend the jobs.CapiModelPrefix if it's missing
		if !strings.HasPrefix(model, jobs.CapiModelPrefix) && model != capi.AutoMode {
			model = jobs.CapiModelPrefix + model
		}

		return model, nil
	}

	// Escape hatch for pre-production or non-CAPI models, only enabled for staff by feature flag.
	// The user has specifically requested a model by a provider
	// (ex: `azopenai:model-not-supported-in-capi` or `sweagent-capi:model-not-in-picker`).
	// NOTE: This intentionally bypasses vendor filtering for third-party agents,
	// allowing staff to override model selection for testing/debugging purposes.
	if strings.Contains(requestedModel, ":") {
		if s.ffs.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgentCanSelectModel, job) {
			return requestedModel, nil
		}
		return "", newErrModelNotFound()
	}

	// Strip the CAPI prefix if present for validation (model IDs in CAPI don't have the prefix)
	modelID := strings.TrimPrefix(requestedModel, jobs.CapiModelPrefix)

	// Validate that the user can access the requested model
	if !userCanAccessModel(modelID, models) {
		return "", newErrModelNotFound()
	}

	// Prepend the jobs.CapiModelPrefix if it's missing
	if !strings.Contains(requestedModel, ":") {
		requestedModel = jobs.CapiModelPrefix + requestedModel
	}

	return requestedModel, nil
}

// useAutoModel returns the canonical "auto" model identifier. The actual
// concrete model is resolved later by the job-fetch handler, which mints a
// CAPI model session and persists the selected model on the job.
//
// For third-party agents (when modelVendors is non-empty), it selects the
// first policy-enabled model from the vendor-filtered list instead, because
// CAPI auto-mode resolution is not available for those agents.
func (s *Service) useAutoModel(ctx context.Context, models []capi.Model, _ *copilotUsersTwirp.CopilotUserDetails, _ githubtwirp.CopilotPlan, job *jobs.Job, modelVendors []string) (string, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "jobservice.useAutoModel")
	defer span.End()
	logger := s.obsv.LoggerWithTelemetry(ctx)

	// When the 3p_auto_model flag is enabled, filter out premium (3x+) models
	// so auto mode only selects 1x models. This prevents users from unknowingly
	// being charged at higher rates when they select "auto".
	if s.ffs.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CodingAgent3PAutoModel, job) {
		models = filterNonPremiumModels(models)
	}

	// For third-party agents, select the first policy-enabled model from the
	// vendor-filtered list. The models list has already been filtered by vendor
	// at this point.
	if len(modelVendors) > 0 {
		for _, model := range models {
			if userCanAccessModel(model.ID, models) {
				logger.Info("using vendor-matched model for third-party agent",
					kvp.String("vendors", strings.Join(modelVendors, ",")),
					kvp.String("model", model.ID),
				)
				return model.ID, nil
			}
		}
		return "", newErrNoModelAvailable()
	}

	// First-party agents defer model selection to the job-fetch handler, which
	// mints a CAPI model session and returns the selected model.
	return capi.AutoMode, nil
}

// userCanAccessModel checks if the user has access to the requested model.
func userCanAccessModel(requestedModel string, models []capi.Model) bool {
	for _, model := range models {
		if model.ID == requestedModel {
			return model.Policy != nil && model.Policy.State != "" && model.Policy.State != capi.ModelPolicyStateDisabled
		}
	}
	return false
}

func (s *Service) mustUseAutoModel(ctx context.Context, plan githubtwirp.CopilotPlan, job *jobs.Job) bool {
	logger := s.obsv.LoggerWithTelemetry(ctx)

	// Must use auto mode for non-Pro/Pro+ plans unless the all-SKUs flag is enabled
	allSkusFlagEnabled := s.ffs.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CodingAgentModelSelectionAllSKUs, job)
	if plan != githubtwirp.CopilotForIndividual && plan != githubtwirp.CopilotForIndividualProPlus &&
		!allSkusFlagEnabled {
		logger.Info("CodingAgentModelSelectionAllSKUs flag is not enabled or plan is not Pro/Pro+, must use auto model",
			kvp.String("plan", string(plan)),
			kvp.String("feature_flag_result", fmt.Sprintf("%v", allSkusFlagEnabled)),
			kvp.Int64("actor_id", job.ActorID),
			kvp.Int64("repo_id", job.RepoID),
			kvp.Int64("owner_id", job.OwnerID),
		)
		return true
	}

	logger.Info("model selection allowed, not required to use auto model")
	return false
}

// filterModelsByVendors returns only the models whose Vendor field matches any of the given vendor strings.
func filterModelsByVendors(models []capi.Model, vendors []string) []capi.Model {
	filtered := make([]capi.Model, 0, len(models))
	for _, model := range models {
		if model.Vendor == nil {
			continue
		}
		for _, vendor := range vendors {
			if strings.EqualFold(*model.Vendor, vendor) {
				filtered = append(filtered, model)
				break
			}
		}
	}
	return filtered
}

// filterNonPremiumModels returns only models that are not premium (billing multiplier <= 1).
// Models without billing info are kept (they may be legacy or test models).
// This is used in auto mode to prevent users from unknowingly being charged
// at premium rates (3x+) when they select "auto".
func filterNonPremiumModels(models []capi.Model) []capi.Model {
	filtered := make([]capi.Model, 0, len(models))
	for _, model := range models {
		if model.Billing != nil && model.Billing.Multiplier > 1 {
			continue
		}
		filtered = append(filtered, model)
	}
	return filtered
}

// isPremiumModelInList checks whether a model ID corresponds to a premium model
// (billing multiplier > 1) in the provided models list. Returns false if the
// model is not found or has no billing info.
func isPremiumModelInList(modelID string, models []capi.Model) bool {
	for _, model := range models {
		if model.ID == modelID {
			return model.Billing != nil && model.Billing.Multiplier > 1
		}
	}
	return false
}

// autoModelExperimentModel checks the ExP SDK assignment for auto model
// experiment flags. When a single treatment variant is assigned, the
// corresponding model is returned. Control and unassigned variants fall
// through to default model selection.
func (s *Service) autoModelExperimentModel(ctx context.Context, job *jobs.Job) (string, bool) {
	if !s.ffs.IsEnabledForUser(ctx, featureflags.CodingAgentAutoModelExperiment, job.ActorID) {
		return "", false
	}

	logger := s.obsv.LoggerWithTelemetry(ctx)
	assignment := exp.AssignmentFromContext(ctx)

	if assignment == nil {
		logger.Warn("auto model experiment: nil assignment from context",
			kvp.Int64("actor_id", job.ActorID),
			kvp.Int64("repo_id", job.RepoID))
		return "", false
	}

	logger.Info("auto model experiment: assignment context",
		kvp.String("assignment_context", assignment.GetAssignmentContext()),
		kvp.Int64("actor_id", job.ActorID),
		kvp.Int64("repo_id", job.RepoID))

	// Control group: emit metric and fall through to default model selection.
	controlFlag, ok := exp.CopilotCodingAgentAutoModel["control"]
	if !ok {
		logger.Warn("auto model experiment: control flag missing",
			kvp.Int64("actor_id", job.ActorID),
			kvp.Int64("repo_id", job.RepoID))
		return "", false
	}
	if assignment.GetBool(exp.FlagKey(controlFlag), false) {
		logger.Info("auto model experiment: control assigned",
			kvp.Int64("actor_id", job.ActorID),
			kvp.Int64("repo_id", job.RepoID))
		s.obsv.Increment(ctx, "jobservice.auto_model_experiment", stats.Tags{"variant": "control"})
		return "", false
	}

	// Treatment variants: return the experiment model.
	keys := make([]string, 0, len(AutoModelExperimentModels))
	for variant := range AutoModelExperimentModels {
		keys = append(keys, variant)
	}
	slices.Sort(keys)

	var chosenVariant, chosenModel string
	var extraVariants []string

	for _, variant := range keys {
		model := AutoModelExperimentModels[variant]
		flag, ok := exp.CopilotCodingAgentAutoModel[variant]
		if !ok {
			logger.Warn("auto model experiment: variant flag missing",
				kvp.String("variant", variant),
				kvp.Int64("actor_id", job.ActorID),
				kvp.Int64("repo_id", job.RepoID))
			continue
		}
		if assignment.GetBool(exp.FlagKey(flag), false) {
			if chosenVariant == "" {
				chosenVariant = variant
				chosenModel = model
			} else {
				extraVariants = append(extraVariants, variant)
			}
		}
	}

	if chosenVariant != "" {
		if len(extraVariants) > 0 {
			logger.Warn("auto model experiment: multiple treatment variants enabled, skipping",
				kvp.String("primary_variant", chosenVariant),
				kvp.String("extra_variants", strings.Join(extraVariants, ",")),
				kvp.Int64("actor_id", job.ActorID),
				kvp.Int64("repo_id", job.RepoID))
			return "", false
		}
		logger.Info("auto model experiment: treatment assigned",
			kvp.String("variant", chosenVariant),
			kvp.String("model", chosenModel),
			kvp.Int64("actor_id", job.ActorID),
			kvp.Int64("repo_id", job.RepoID))
		s.obsv.Increment(ctx, "jobservice.auto_model_experiment", stats.Tags{"variant": chosenVariant})
		return chosenModel, true
	}

	logger.Info("auto model experiment: no variant assigned",
		kvp.Int64("actor_id", job.ActorID),
		kvp.Int64("repo_id", job.RepoID))
	return "", false
}

// BuildModelSelectionInfo resolves model selection metadata for engines that
// support dynamic model selection. It queries CAPI for the user's available
// models, filters by the agent's vendor, and returns the information needed
// for the engine to select a model.
//
// If cachedModels is non-nil, it will be used instead of making a fresh CAPI
// call, avoiding a duplicate ListCodingAgentModels request when the caller
// has already fetched the model list (e.g. during DetermineModel).
//
// Returns nil when the CodingAgentModelSelectionInJobResponse feature flag
// is not enabled, when the agent has no vendor (i.e. the agent is not
// vendor-specific), or when no models are available after filtering.
func (s *Service) BuildModelSelectionInfo(ctx context.Context, job *jobs.Job, agentID int64, cachedModels []capi.Model) *jobs.ModelSelectionInfo {
	ctx, span := s.obsv.Tracer.Start(ctx, "jobservice.BuildModelSelectionInfo")
	defer span.End()
	logger := s.obsv.LoggerWithTelemetry(ctx)

	if !s.ffs.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CodingAgentModelSelectionInJobResponse, job) {
		return nil
	}

	agent, err := s.appProvider.FindByID(ctx, agentID)
	if err != nil {
		logger.WithError(err).Warn("failed to find agent for model selection info",
			kvp.Int64("agent_id", agentID))
		return nil
	}

	vendors := agent.ModelVendors()
	if len(vendors) == 0 {
		return nil
	}

	allModels := cachedModels
	if allModels == nil {
		// Use the agent's CAPI integration ID (if set) so that CAPI can
		// identify the specific agent integration on /models calls.
		capiCtx := ctx
		if s.ffs.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CodingAgentCAPI3pIntegrationID, job) {
			if integrationID := agent.Metadata()[sweagentd.MetadataCAPIIntegrationID]; integrationID != "" {
				capiCtx = capi.ContextWithCAPIIntegrationID(capiCtx, integrationID)
			}
		}
		var capiErr error
		allModels, capiErr = s.capi.ListCodingAgentModels(capiCtx, uint64(job.ActorID), string(job.ActorType))
		if capiErr != nil {
			logger.WithError(capiErr).Warn("failed to list models for model selection info")
			return nil
		}
	}

	filtered := filterModelsByVendors(allModels, vendors)

	modelIDs := make([]string, 0, len(filtered))
	for _, m := range filtered {
		if m.Policy != nil && m.Policy.State != "" && m.Policy.State != capi.ModelPolicyStateDisabled {
			modelIDs = append(modelIDs, m.ID)
		}
	}

	if len(modelIDs) == 0 {
		return nil
	}

	// Prefer the job's already-selected model as the default when it is
	// present in the available set; otherwise fall back to the first entry.
	defaultModel := modelIDs[0]
	jobModel := strings.TrimPrefix(job.Model, jobs.CapiModelPrefix)
	for _, id := range modelIDs {
		if strings.TrimPrefix(id, jobs.CapiModelPrefix) == jobModel {
			defaultModel = id
			break
		}
	}

	logger.Info("built model selection info for engine",
		kvp.String("vendors", strings.Join(vendors, ",")),
		kvp.String("engine", agent.ComputeSlug()),
		kvp.Int("available_model_count", len(modelIDs)),
	)

	return &jobs.ModelSelectionInfo{
		Enabled:         true,
		Vendors:         vendors,
		DefaultModel:    defaultModel,
		AvailableModels: modelIDs,
	}
}
