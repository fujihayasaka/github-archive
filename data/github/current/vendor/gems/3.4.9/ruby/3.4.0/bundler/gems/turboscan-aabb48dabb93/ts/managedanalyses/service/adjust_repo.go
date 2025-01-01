package managedanalyses

import (
	"context"

	"github.com/github/turboscan/ts/appctx"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/o11y"

	"github.com/pkg/errors"
)

// AdjustRepo modifies a staged configuration for a repository to reflect the result of the validation run.
func (ma *ManagedAnalyses) AdjustRepo(ctx context.Context, repoID ts.RepositoryEID, langs ts.Languages, runID ts.WorkflowRunEID) error {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	// TODO: This is missing org information
	codeQLWorkflow := func(config *ts.CodeqlConfig) (string, error) {
		tmpl := ma.WorkflowsLibrary.GetWorkflowTemplateByVersion(ctx, repoID, config.TemplateVersion)
		return tmpl.CodeQLWorkflow(config)
	}

	return adjustRepo(ctx, ma.DataService.GetCodeqlRepo, ma.DataService.AdjustCodeqlConfigLanguages, codeQLWorkflow, repoID, langs, runID)
}

func adjustRepo(ctx context.Context, getCodeqlRepo func(context.Context, ts.RepositoryEID) (*ts.CodeqlRepo, error), adjustCodeqlConfig func(context.Context, ts.CodeqlConfigID, ts.Languages, string) error, codeQLWorkflow func(*ts.CodeqlConfig) (string, error), repoID ts.RepositoryEID, langs ts.Languages, runID ts.WorkflowRunEID) error {
	repo, err := getCodeqlRepo(ctx, repoID)
	if err != nil {
		if errors.Is(err, ts.ErrCodeqlRepoNotFound) {
			return ts.ErrNotOnboarding
		}
		return errors.Wrap(err, "couldn't retrieve the existing configuration")
	}

	if repo.OnboardingStatus() != ts.OnboardingStatus_ONBOARDING {
		appctx.Logger(ctx).Info("Couldn't adjust the repository config because it is not enabling", repoID.AsKVP())
		return ts.ErrNotOnboarding
	}

	stagedConfig := repo.StagedConfig

	if runID != 0 {
		if stagedConfig.ValidationRun != nil && runID != stagedConfig.ValidationRun.WorkflowRunID {
			// The adjust call is from a workflow run that is not the latest validation run
			return ts.ErrWrongWorkflowRun
		} else if stagedConfig.ValidationRun == nil {
			return errors.New("validation run is missing")
		}
	}

	// If the languages are the same, there is nothing to do
	if stagedConfig.Languages.Equals(langs) {
		return nil
	}
	if !isValidAdjustment(stagedConfig, langs) {
		return errors.New("invalid adjustment")
	}

	// Update the languages for the config, and re-generate the workflow file to only use those.
	stagedConfig.Languages = langs
	newWorkflow, err := codeQLWorkflow(stagedConfig)
	if err != nil {
		return errors.Wrap(err, "couldn't regenerate the workflow for the config")
	}
	stagedConfig.Workflow = newWorkflow
	err = adjustCodeqlConfig(ctx, stagedConfig.ID, langs, newWorkflow)
	if err != nil {
		return errors.Wrap(err, "couldn't update the staged configuration")
	}

	return nil
}

// isValidAdjustment checks if the adjustment is valid. This means that the
// new set of languages is a subset of the old set of languages.
func isValidAdjustment(oldConfig *ts.CodeqlConfig, lang ts.Languages) bool {
	// Create a set from the old languages
	oldLangSet := make(map[string]struct{})
	for _, l := range oldConfig.Languages {
		oldLangSet[l] = struct{}{}
	}

	// Check if all languages in lang are in oldLangSet
	for _, l := range lang {
		if _, ok := oldLangSet[l]; !ok {
			return false
		}
	}

	return true
}
