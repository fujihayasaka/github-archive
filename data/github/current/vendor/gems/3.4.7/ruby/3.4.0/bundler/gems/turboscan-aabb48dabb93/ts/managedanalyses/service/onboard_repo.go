package managedanalyses

import (
	"context"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/flipper"
	"github.com/github/turboscan/ts/o11y"

	ma_ "github.com/github/turboscan/ts/managedanalyses"
	"github.com/pkg/errors"
)

// OnboardRepo onboards a repository to Managed Analyses.
// This involves creating/updating a CodeQLConfig, and triggering a validation run
// by sending a CodeQLRun to Actions' Dynamic Workflows API.
// It returns the WorkflowRunID of the validation run that was triggered.
func (ma *ManagedAnalyses) OnboardRepo(ctx context.Context, repoID ts.RepositoryEID, languages ts.Languages, querySuite ts.QuerySuite, threatModel ts.ThreatModel, actor *ts.ActorGRIDLogin, defaultRef []byte, ownerID ts.OwnerEID, codeqlPacks ts.CodeqlPacks, runnerLabel string) (ts.WorkflowRunEID, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	if len(defaultRef) == 0 {
		return 0, errors.New("default ref must be specified for onboarding")
	}

	if ma.LaunchApiClient == nil {
		return 0, errors.New("Cannot onboard repository: Actions is not configured.")
	}

	codeqlRepo, err := ma.DataService.GetCodeqlRepo(ctx, repoID)
	if err != nil {
		return 0, errors.Wrap(err, "failed to get repository configuration")
	}

	// If there is already a CodeQLConfig (either validated or in the process of being validated),
	// then we shouldn't try to re-onboard
	if c := codeqlRepo.StagedConfig; c != nil {
		return c.ValidationRun.WorkflowRunID, ts.ErrNoChangeRequired
	} else if c := codeqlRepo.CurrentConfig; c != nil {
		return c.ValidationRun.WorkflowRunID, ts.ErrNoChangeRequired
	}

	// Create CodeQLConfig
	config := &ts.CodeqlConfig{
		RepositoryID:            codeqlRepo.RepositoryID,
		RepositoryGRID:          codeqlRepo.RepositoryGRID,
		UsingCombinedLanguages:  codeqlRepo.UsingCombinedLanguages,
		JavaExtractionOptions:   codeqlRepo.JavaExtractionOptions,
		CSharpExtractionOptions: codeqlRepo.CSharpExtractionOptions,
		CppExtractionOptions:    codeqlRepo.CppExtractionOptions,
		RunnerLabel:             runnerLabel,
		Languages:               ts.NormalizeLanguages(languages),
		InitialLanguages:        ts.NormalizeLanguages(languages),
		OnboardedByActorGRID:    actor.GRID,
		CreatedByActorLogin:     actor.Login,
		QuerySuiteType:          querySuite.QuerySuiteType(),
		ThreatModel:             threatModel,
	}

	// Forcing the FF for the entire job because we do not have the owner information everywhere
	if flipper.HasSuggestedFixIncludeCCRQuality(ctx, ownerID, repoID) {
		ctx = flipper.WithFeatureEnabled(ctx, flipper.CodeScanningSuggestedFixIncludesQuality)
	}

	wf := ma.WorkflowsLibrary.GetWorkflowTemplate(ctx, codeqlRepo.RepositoryID)
	run, err := config.SetUpForValidationRunWithAutoAdjust(defaultRef, ts.EmptySha, wf, ts.CodeqlRunTriggeringEvent_VALIDATION, ownerID, codeqlPacks)
	if err != nil {
		return 0, errors.Wrap(err, "failed to create validation run")
	}

	// Call Dynamic Workflows
	err = ma.LaunchApiClient.RunDynamicWorkflow(ctx, run)
	if err != nil {
		return 0, errors.Wrap(err, "failed to trigger dynamic workflow")
	}
	ma_.DynamicWorkflowRunLogAndStats(ctx, config, run)

	scheduledRunAt := ma.Scheduler.GetRandomScheduleTime()
	err = ma.DataService.WithTransaction(func(tx ma_.CodeqlDB) error {
		err = tx.CreateStagedCodeqlConfig(ctx, config)
		if err != nil {
			return errors.Wrap(err, "failed to enable managed analysis")
		}

		err = tx.CreateCodeqlRun(ctx, run)
		if err != nil {
			return errors.Wrap(err, "failed to create codeql_run")
		}

		err = tx.CreateCodeqlSchedule(ctx, codeqlRepo.RepositoryID, scheduledRunAt)
		if err != nil {
			return errors.Wrap(err, "failed to create the codeql schedule entry")
		}

		return nil
	})

	if err != nil {
		return 0, errors.Wrap(err, "failed to onboard into default setup")
	}

	return run.WorkflowRunID, nil
}
