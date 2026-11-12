package jobservice

import (
	"context"
	"strings"

	copilotUsersTwirp "github.com/github/copilot-twirp/proto/users/v1"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/sweagentd/internal/experiments"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/sweagentd"
)

const modelLabelPrefix = "copilot:agent="

// DefaultModel model is the model that is used by the agent when the `sweagentd_use_candidate_model_as_default` feature flag is not enabled
// and an explicit model label has not been applied.
const DefaultModel = "sweagent-capi:claude-sonnet-4"

// DefaultModelForBusinessOrPro is the model that is used instead of [DefaultModel] when the user is a Business or Pro user.
// For capacity or cost reasons, we may use a different model for these users.
const DefaultModelForBusinessOrPro = "sweagent-capi:claude-sonnet-4"

// DaisyModel is the model that is used by the agent when the `sweagentd_use_daisy_model_pro_and_pro_plus` feature flag is enabled
// and the user has the Daisy policy enabled.
const DaisyModel = "sweagent-capi:claude-sonnet-4.5"

// CandidateModel is the model that is used by the agent when the `sweagentd_use_candidate_model_as_default` feature flag is enabled.
const CandidateModel = DaisyModel

// leaving this commented out to provide example of how to enable experimental models in future
// if no experiments are running, comment this to ensure traffic defaults to the DefaultModel
// ExperimentalModel1 is the model that is used by the agent when the `ModelCompareExperiment` variant returns 1.
// const ExperimentalModel1 = "sweagent-capi:oswe"

// ExperimentalModel2 is the model that is used by the agent when the `ModelCompareExperiment` variant returns 2.
// const ExperimentalModel2 = "sweagent-capi:oswe-prime"

// ExperimentalModels is a map of experimental models that can be used.
var ExperimentalModels = map[int]string{
	// 1: ExperimentalModel1,
	// 2: ExperimentalModel2,
}

// determineModel determines the model to use when the agent is launched based on the labels applied to an item (e.g. issue or PR) as
// well as the feature flags that are enabled for the actor, repo or repo owner.
func determineModel(ctx context.Context, obsv observability.Exporters, ffClient featureflags.Client, twirpClient githubtwirp.ClientInterface, job *jobs.Job, labelMetadata sweagentd.LabelMetadata) string {
	logger := obsv.LoggerWithTelemetry(ctx)

	// Check if we should use an experimental OSWE model
	if job.Experiments != nil && job.Experiments.Variations != nil {
		if value, ok := job.Experiments.Variations[experiments.ModelCompareExperiment]; ok {
			if intVal, ok := value.(int); ok && intVal != 0 {
				if model, ok := ExperimentalModels[intVal]; ok {
					logger.Info("using experimental model provided by exp", kvp.Int("experiment_value", intVal), kvp.String("model", model))
					return model
				}
			}
		}
	}

	// If explicitly setting a model via a label is allowed and a model label is present, use that model.
	if labelMetadata.HasModel() {
		logger.Info("using explicit model provided by label", kvp.String("model", labelMetadata.Model))
		return labelMetadata.Model
	}

	// If the actor, owner or repo has been feature flagged into the candidate model, use that model.
	if ffClient.IsEnabledForUserOrRepoOrOwner(ctx, "sweagentd_use_candidate_model_as_default", job) {
		logger.Info("using candidate model due to feature flag enabled for actor, repo or owner", kvp.String("model", CandidateModel))
		return CandidateModel
	}

	// If the Daisy feature flag and policy is enabled, use that - otherwise continue with standard checks.
	userDetails, err := githubtwirp.GetCopilotUserDetails(ctx, twirpClient, job.ActorID)
	if err != nil {
		logger.WithError(err).Error("failed to get Copilot user details for user, using default business or pro model", kvp.String("model", DefaultModelForBusinessOrPro))
		return DefaultModelForBusinessOrPro
	}

	plan, err := githubtwirp.CopilotPlanFromUser(userDetails)
	if err != nil {
		logger.WithError(err).Error("failed to get Copilot plan for user, using default business or pro model", kvp.String("model", DefaultModelForBusinessOrPro))
		return DefaultModelForBusinessOrPro
	}

	if useDaisyModel(ctx, obsv, ffClient, userDetails, plan, job) {
		logger.Info("using Daisy model due to Daisy policy enabled for user", kvp.String("model", DaisyModel))
		return DaisyModel
	}

	if plan == githubtwirp.CopilotForBusiness || plan == githubtwirp.CopilotForIndividual {
		logger.Info("Using business or pro model for Copilot user due to plan", kvp.String("plan", string(plan)), kvp.String("model", DefaultModelForBusinessOrPro))
		return DefaultModelForBusinessOrPro
	}

	logger.Info("Using default model", kvp.String("plan", string(plan)), kvp.String("model", DefaultModel))
	return DefaultModel
}

func useDaisyModel(ctx context.Context, obsv observability.Exporters, ffClient featureflags.Client, copilotUser *copilotUsersTwirp.CopilotUserDetails, plan githubtwirp.CopilotPlan, job *jobs.Job) bool {
	logger := obsv.LoggerWithTelemetry(ctx)

	// If the user is on paid Individual plan, they always get Daisy (if ff enabled)
	if plan.IsPaidIndividual() {
		if !ffClient.IsEnabledForUserOrRepoOrOwner(ctx, "sweagentd_use_daisy_model_pro_and_pro_plus", job) {
			// Feature flag isn't enabled, don't use Daisy model.
			logger.Info("not using Daisy model, paid individual user does not have ff enabled")
			return false
		}

		logger.Info("using Daisy model due to user being on paid Individual plan")
		return true
	}

	// Use Daisy if the user has the Daisy policy enabled
	if !ffClient.IsEnabledForUserOrRepoOrOwner(ctx, "sweagentd_use_daisy_model_if_policy_enabled_for_user", job) {
		// Feature flag isn't enabled, don't use Daisy model.
		logger.Info("not using Daisy model as sweagentd_use_daisy_model_if_policy_enabled_for_user not enabled for actor, repo or owner")
		return false
	}

	if copilotUser.DaisySetting == copilotUsersTwirp.Daisy_DAISY_ENABLED {
		logger.Info("daisy policy enabled for user, using Daisy model")
		return true
	}

	logger.Info("not using Daisy model")
	return false
}

// GetModelFromLabels returns the model name from the labels with the form "copilot:agent=<model_name>". It returns "" if
// no such label is found.
func GetModelFromLabels[E interface{ GetName() string }](labels []E) string {
	for _, label := range labels {
		if strings.HasPrefix(label.GetName(), modelLabelPrefix) {
			var after, _ = strings.CutPrefix(label.GetName(), modelLabelPrefix)
			return after
		}
	}

	return ""
}

// DetermineModel is a convenience function for calling determineModel with LabelMetadata.
func (s *Service) DetermineModel(ctx context.Context, job *jobs.Job, labelMetaData sweagentd.LabelMetadata) string {
	ctx, span := s.obsv.Tracer.Start(ctx, "jobservice.DetermineModel")
	defer span.End()

	return determineModel(ctx, s.obsv, s.ffs, s.twirp, job, labelMetaData)
}

// DetermineModelWithLabelNames is a convenience function for calling DetermineModel with an array of label names represented as strings.
func (s *Service) DetermineModelWithLabelNames(ctx context.Context, job *jobs.Job, labelNames []string) string {
	ctx, span := s.obsv.Tracer.Start(ctx, "jobservice.DetermineModelWithLabelNames")
	defer span.End()

	labels := make([]github.GQLLabel, 0, len(labelNames))
	for _, name := range labelNames {
		labels = append(labels, github.GQLLabel{
			Name: name,
		})
	}

	labelMetadata := LabelMetadataWithChecks(ctx, s.ffs, job, labels)
	return determineModel(ctx, s.obsv, s.ffs, s.twirp, job, labelMetadata)
}
