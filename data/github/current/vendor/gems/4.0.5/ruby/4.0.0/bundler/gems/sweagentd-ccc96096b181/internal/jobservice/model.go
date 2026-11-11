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
	"github.com/github/sweagentd/internal/experiments"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/jobs"
)

var (
	// ErrModelNotFound is returned when the requested model is not found or not enabled for the user.
	ErrModelNotFound = errors.New("model not found or not enabled for user")
	// ErrNoModelAvailable is returned when no coding-agent-capable models are available for the user (due to policies or feature flags).
	ErrNoModelAvailable = errors.New("no model available for user")
)

func newErrModelNotFound() error {
	return goerrors.WithStackOffset(ErrModelNotFound, 1)
}

func newErrNoModelAvailable() error {
	return goerrors.WithStackOffset(ErrNoModelAvailable, 1)
}

// CapiModelPrefix is the prefix used for models provided by CAPI.
const CapiModelPrefix = "sweagent-capi:"

// stripModelPrefix removes the CAPI prefix from a model name if present.
// This is used when sending model information to external services (like the session service)
// that should not be exposed to this implementation detail.
func stripModelPrefix(model string) string {
	return strings.TrimPrefix(model, CapiModelPrefix)
}

// ExperimentalModel1 is the model that is used by the agent when the `ModelCompareExperiment` variant returns 1.
// const ExperimentalModel1 = CapiModelPrefix + "claude-opus-4.5"

// ExperimentalModel2 is the model that is used by the agent when the `ModelCompareExperiment` variant returns 2.
// const ExperimentalModel2 = "sweagent-capi:oswe-prime"

// ExperimentalModels is a map of experimental models that can be used.
var ExperimentalModels = map[int]string{
	// 1: ExperimentalModel1,
	// 2: ExperimentalModel2,
}

// AutoModels is the list of models that can be selected when "auto" mode is enabled.
// The order of this list matters, as the first model that the user has access to will be selected.
var AutoModels = []string{
	capi.ClaudeSonnet45,
}

// FallbackAutoModel is the model that is used when no other models are available in auto mode.
var FallbackAutoModel = capi.ClaudeSonnet45

// DetermineModel determines the model to use when the agent is launched based on the feature flags
// and experiments that are enabled for the actor, repo or repo owner.
func (s *Service) DetermineModel(ctx context.Context, requestedModel string, job *jobs.Job) (string, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "jobservice.DetermineModel")
	defer span.End()
	logger := s.obsv.LoggerWithTelemetry(ctx)

	// Get a list of the models that the user is allowed to use. We need this list to
	// validate which models the user can select from, or to choose from in auto mode.
	models, err := s.capi.ListCodingAgentModels(ctx, uint64(job.ActorID))
	if err != nil {
		return "", goerrors.Errorf("listing models: %w", err)
	}

	// The user doesn't have any coding-agent models available, likely because
	// their Copilot license has all of the model policies disabled.
	if len(models) == 0 {
		logger.Info("no models available for user")
		return "", newErrNoModelAvailable()
	}

	// Default to "auto" if no model is specified
	if requestedModel == "" {
		requestedModel = capi.AutoMode
	}

	userDetails, err := s.twirp.GetCopilotUserDetails(ctx, job.ActorID)
	if err != nil {
		logger.WithError(err).Error("failed to get Copilot user details for user, using default model", kvp.String("model", capi.ClaudeSonnet45))
		return "", goerrors.Errorf("getting copilot user details: %w", err)
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
	} else if !strings.Contains(requestedModel, ":") && slices.Contains(capi.CodingAgentModelIDs, requestedModel) {
		requestedModelTag = requestedModel
	}
	s.obsv.Increment(ctx, "jobservice.model_requested", stats.Tags{"model": requestedModelTag})

	model, err := s.determineModel(ctx, requestedModel, models, userDetails, plan, job, useAuto)
	if err != nil {
		return "", goerrors.Errorf("determining model: %w", err)
	}

	logger.Info("determined model", kvp.String("model", model))
	s.obsv.Increment(ctx, "jobservice.model_determined", stats.Tags{"auto": fmt.Sprintf("%t", useAuto), "model": model})
	return model, nil
}

func (s *Service) determineModel(ctx context.Context, requestedModel string, models []capi.Model, userDetails *copilotUsersTwirp.CopilotUserDetails, plan githubtwirp.CopilotPlan, job *jobs.Job, useAuto bool) (string, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "jobservice.determineModel")
	defer span.End()

	if useAuto {
		model, err := s.useAutoModel(ctx, models, userDetails, plan, job)
		if err != nil {
			return "", err
		}

		// Prepend the CapiModelPrefix if it's missing
		if !strings.HasPrefix(model, CapiModelPrefix) {
			model = CapiModelPrefix + model
		}

		return model, nil
	}

	// Escape hatch for pre-production or non-CAPI models, only enabled for staff by feature flag
	// The user has specifically requested a model by a provider
	// (ex: `azopenai:model-not-supported-in-capi` or `sweagent-capi:model-not-in-picker`).
	if strings.Contains(requestedModel, ":") {
		if s.ffs.IsEnabledForUserOrRepoOrOwner(ctx, featureflags.CopilotSWEAgentCanSelectModel, job) {
			return requestedModel, nil
		}
		return "", newErrModelNotFound()
	}

	// Strip the CAPI prefix if present for validation (model IDs in CAPI don't have the prefix)
	modelID := strings.TrimPrefix(requestedModel, CapiModelPrefix)

	// Validate that the user can access the requested model
	if !userCanAccessModel(modelID, models) {
		return "", newErrModelNotFound()
	}

	// Prepend the CapiModelPrefix if it's missing
	if !strings.Contains(requestedModel, ":") {
		requestedModel = CapiModelPrefix + requestedModel
	}

	return requestedModel, nil
}

// useAutoModel determines the model to use when "auto" mode is selected based on
// the user's Copilot plan, policies, feature flags, and experiments.
// TODO: Use a combination of the user's plan, and which models are available to them via CAPI (models parameter)
// to determine which model to use. For now, we just use Opus if we can, otherwise Sonnet.
func (s *Service) useAutoModel(ctx context.Context, models []capi.Model, userDetails *copilotUsersTwirp.CopilotUserDetails, plan githubtwirp.CopilotPlan, job *jobs.Job) (string, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "jobservice.useAutoModel")
	defer span.End()
	logger := s.obsv.LoggerWithTelemetry(ctx)

	// Check if we should use an experimental OSWE model
	if job.Experiments != nil && job.Experiments.Variations != nil {
		if value, ok := job.Experiments.Variations[experiments.ModelCompareExperiment]; ok {
			if intVal, ok := value.(int); ok && intVal != 0 {
				if model, ok := ExperimentalModels[intVal]; ok {
					logger.Info("using experimental model provided by exp", kvp.Int("experiment_value", intVal), kvp.String("model", model))
					return model, nil
				}
			}
		}
	}

	// First, prefer Opus 4.5 but behind a flag:
	if plan == githubtwirp.CopilotForBusiness || plan == githubtwirp.CopilotForEnterprise {
		logger.Info("User is on business or enterprise plan, checking Opus FF", kvp.String("plan", string(plan)))

		if s.ffs.IsEnabledForUserOrRepoOrOwner(ctx, "copilot_swe_agent_use_opus_model_for_cfb_users_with_policy_enabled", job) {
			logger.Info("Opus CfB FF is enabled for user/repo/owner, checking policy")

			if userDetails.LotusSetting == copilotUsersTwirp.Lotus_LOTUS_ENABLED {
				logger.Info("Opus policy is enabled for user, using Opus model", kvp.String("plan", string(plan)), kvp.String("model", capi.ClaudeOpus45))
				return capi.ClaudeOpus45, nil
			}
		}
	} else if s.ffs.IsEnabledForUserOrRepoOrOwner(ctx, "copilot_swe_agent_use_opus_model_for_individual_users", job) {
		logger.Info("Opus CfI FF is enabled for user/repo/owner, using Opus model", kvp.String("plan", string(plan)), kvp.String("model", capi.ClaudeOpus45))
		return capi.ClaudeOpus45, nil
	}

	if plan == githubtwirp.CopilotForIndividualFree {
		if s.ffs.IsEnabledForUser(ctx, featureflags.CodingAgentFreeUsersExperiment, int64(userDetails.Id)) {
			logger.Info("user is on free plan and experiment flag is enabled, using Sonnet model", kvp.String("model", capi.ClaudeSonnet45))
			return capi.ClaudeSonnet45, nil
		}

		logger.Info("user is on free plan but experiment flag is disabled, cannot use any model")
		return "", newErrNoModelAvailable()
	}

	// Next, iterate through the preferred auto models and
	// return the first one that the user can access
	for _, model := range AutoModels {
		// Check if the model is allowed for the user's plan
		if userCanAccessModel(model, models) {
			logger.Info("using preferred auto model for user", kvp.String("model", model))
			return model, nil
		}
	}

	// The user isn't allowed to use any of the preferred auto models, so fall back to a default model
	logger.Info("no preferred auto models available for user, using fallback model", kvp.String("model", FallbackAutoModel))
	return FallbackAutoModel, nil
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
