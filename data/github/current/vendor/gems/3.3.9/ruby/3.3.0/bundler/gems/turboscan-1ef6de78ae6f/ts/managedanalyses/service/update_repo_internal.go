package managedanalyses

import (
	"context"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/flipper"
	ma_ "github.com/github/turboscan/ts/managedanalyses"
	"github.com/github/turboscan/ts/o11y"
	"github.com/pkg/errors"
)

func (ma *ManagedAnalyses) updateRepo(
	ctx context.Context,
	codeqlRepo *ts.CodeqlRepo,
	triggeringEvent ts.CodeqlRunTriggeringEvent,
	newSupportedLanguages ts.Languages,
	// New Config Values
	newSelectedLanguages *ts.Languages,
	newQuerySuite *ts.QuerySuite,
	newThreatModel *ts.ThreatModel,
	// Data needed for validation run:
	defaultRef ts.Ref,
	ownerID ts.OwnerEID,
	// Dynamic input
	codeqlPacks ts.CodeqlPacks,
	// Who triggered the update
	actor *ts.ActorGRIDLogin,
	useCodeScanningRunnerLabel bool,
	runnerLabel string,
) (ts.WorkflowRunEID, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	if codeqlRepo == nil || !codeqlRepo.IsEnabled() {
		return 0, ts.ErrCodeqlRepoNotEnabled
	}

	codeqlRepo.SupportedLanguages = newSupportedLanguages
	err := ma.DataService.UpdateCodeqlRepo(ctx, codeqlRepo)
	if err != nil {
		return 0, err
	}

	if codeqlRepo.IsOnboarding() || codeqlRepo.IsUpdating() {
		return ma.checkEquivalentUpdate(codeqlRepo, newSelectedLanguages, newQuerySuite, newThreatModel, actor, useCodeScanningRunnerLabel, runnerLabel)
	}

	if codeqlRepo.IsWaiting() {
		return ma.updateWaitingRepo(
			ctx,
			codeqlRepo,
			// New Config Values
			newSelectedLanguages,
			newQuerySuite,
			newThreatModel,
			// Data needed for validation run:
			defaultRef,
			ownerID,
			// Dynamic input
			codeqlPacks,
			// Who triggered the update
			actor,
			useCodeScanningRunnerLabel,
			runnerLabel,
		)
	}

	if codeqlRepo.IsStable() {
		return ma.updateStableRepo(
			ctx,
			codeqlRepo,
			triggeringEvent,
			// New Config Values
			newSelectedLanguages,
			newQuerySuite,
			newThreatModel,
			// Data needed for validation run:
			defaultRef,
			ownerID,
			codeqlPacks,
			// Who triggered the update
			actor,
			useCodeScanningRunnerLabel,
			runnerLabel,
		)
	}

	panic("unreachable")
}

// checkEquivalentUpdate checks if the new values are equivalent to the current staged config
// if they are not, it returns an error
func (ma *ManagedAnalyses) checkEquivalentUpdate(
	codeqlRepo *ts.CodeqlRepo,
	selectedLanguages *ts.Languages,
	querySuite *ts.QuerySuite,
	threatModel *ts.ThreatModel,
	actor *ts.ActorGRIDLogin,
	useCodeScanningRunnerLabel bool,
	runnerLabel string,
) (ts.WorkflowRunEID, error) {
	newSelectedLanguages := Coalesce(selectedLanguages, codeqlRepo.StagedConfig.Languages)
	newQuerySuite := Coalesce(querySuite, codeqlRepo.StagedConfig.QuerySuiteType.Root())
	newThreatModel := Coalesce(threatModel, codeqlRepo.StagedConfig.ThreatModel)

	updatedConfig := codeqlRepo.StagedConfig.NewUpdatedConfig(
		newSelectedLanguages,
		newQuerySuite,
		newThreatModel,
		useCodeScanningRunnerLabel,
		runnerLabel,
		actor,
	)

	if codeqlRepo.StagedConfig.IsEquivalent(updatedConfig) {
		return codeqlRepo.StagedConfig.ValidationRun.WorkflowRunID, ts.ErrNoChangeRequired
	} else {
		return 0, ts.ErrCodeqlConfigConflict
	}
}

// updateWaitingRepo will try to onboard a repo if there are newSelectedLanguages
// or if there aren't, just update the fields for the codeqlRepo
func (ma *ManagedAnalyses) updateWaitingRepo(
	ctx context.Context,
	codeqlRepo *ts.CodeqlRepo,
	// New Config Values
	selectedLanguages *ts.Languages,
	querySuite *ts.QuerySuite,
	threatModel *ts.ThreatModel,
	// Data needed for validation run:
	defaultRef ts.Ref,
	ownerID ts.OwnerEID,
	// Dynamic input
	codeqlPacks ts.CodeqlPacks,
	// Who triggered the update
	actor *ts.ActorGRIDLogin,
	usingCSRunnerLabel bool,
	runnerLabel string,
) (ts.WorkflowRunEID, error) {
	newSelectedLanguages := Coalesce(selectedLanguages, make(ts.Languages, 0))
	newQuerySuite := Coalesce(querySuite, codeqlRepo.QuerySuite)
	newThreatModel := Coalesce(threatModel, codeqlRepo.ThreatModel)

	if len(newSelectedLanguages) > 0 {
		return ma.OnboardRepo(ctx, codeqlRepo.RepositoryID, newSelectedLanguages, newQuerySuite, newThreatModel, actor, defaultRef, ownerID, codeqlPacks, usingCSRunnerLabel, runnerLabel)
	} else {
		codeqlRepo.QuerySuite = newQuerySuite
		codeqlRepo.ThreatModel = newThreatModel
		codeqlRepo.UsingCSRunnerLabel = usingCSRunnerLabel
		codeqlRepo.RunnerLabel = runnerLabel
		err := ma.DataService.UpdateCodeqlRepo(ctx, codeqlRepo)
		return 0, err
	}
}

// updateStableRepo will try to offboard a repo if there are no newSelectedLanguages
// or if there are, trigger a config update
func (ma *ManagedAnalyses) updateStableRepo(
	ctx context.Context,
	codeqlRepo *ts.CodeqlRepo,
	triggeringEvent ts.CodeqlRunTriggeringEvent,
	// New Config Values
	selectedLanguages *ts.Languages,
	querySuite *ts.QuerySuite,
	threatModel *ts.ThreatModel,
	// Data needed for validation run:
	defaultRef ts.Ref,
	ownerID ts.OwnerEID,
	// Dynamic input
	codeqlPacks ts.CodeqlPacks,
	// Who triggered the update
	actor *ts.ActorGRIDLogin,
	useCodeScanningRunnerLabel bool,
	runnerLabel string,
) (ts.WorkflowRunEID, error) {
	newSelectedLanguages := Coalesce(selectedLanguages, codeqlRepo.CurrentConfig.Languages)
	newQuerySuite := Coalesce(querySuite, codeqlRepo.CurrentConfig.QuerySuiteType.Root())
	newThreatModel := Coalesce(threatModel, codeqlRepo.CurrentConfig.ThreatModel)

	if len(newSelectedLanguages) == 0 {
		err := ma.OffboardRepo(ctx, codeqlRepo.RepositoryID)
		if err != nil {
			return 0, err
		}

		codeqlRepo, err = ma.DataService.GetCodeqlRepo(ctx, codeqlRepo.RepositoryID)
		if err != nil {
			return 0, err
		}
		codeqlRepo.QuerySuite = newQuerySuite
		codeqlRepo.ThreatModel = newThreatModel
		codeqlRepo.UsingCSRunnerLabel = useCodeScanningRunnerLabel
		codeqlRepo.RunnerLabel = runnerLabel
		err = ma.DataService.UpdateCodeqlRepo(ctx, codeqlRepo)
		return 0, err
	} else {
		updatedConfig := codeqlRepo.CurrentConfig.NewUpdatedConfig(
			newSelectedLanguages,
			newQuerySuite,
			newThreatModel,
			useCodeScanningRunnerLabel,
			runnerLabel,
			actor,
		)

		// If the update is a noop, we should return the workflow_id for the latest validation run
		if updatedConfig.IsEquivalent(codeqlRepo.CurrentConfig) {
			return codeqlRepo.CurrentConfig.ValidationRun.WorkflowRunID, ts.ErrNoChangeRequired
		}

		if flipper.HasCodeScanningCustomRunnerLabels(ctx, ownerID, codeqlRepo.RepositoryID) && onlyRunnerLabelUpdated(*updatedConfig, *codeqlRepo.CurrentConfig) && ma.usesCurrentWorkflowVersion(ctx, codeqlRepo) {
			err := ma.updateCodeqlConfig(ctx, codeqlRepo, useCodeScanningRunnerLabel, runnerLabel, actor)
			if err != nil {
				return 0, err
			}
			return 0, ts.ErrNoChangeRequired
		}

		return ma.triggerCodeqlConfigUpdate(
			ctx,
			codeqlRepo.RepositoryID,
			updatedConfig,
			triggeringEvent,
			defaultRef,
			ownerID,
			codeqlPacks,
		)
	}
}

func (ma *ManagedAnalyses) updateCodeqlConfig(ctx context.Context, codeqlRepo *ts.CodeqlRepo, useCodeScanningRunnerLabel bool, runnerLabel string, actor *ts.ActorGRIDLogin) error {
	codeqlConfig := codeqlRepo.CurrentConfig.CopyForUpdate()
	codeqlConfig.UsingCSRunnerLabel = useCodeScanningRunnerLabel
	codeqlConfig.RunnerLabel = runnerLabel
	codeqlConfig.OnboardedByActorGRID = actor.GRID
	codeqlConfig.CreatedByActorLogin = actor.Login

	// Render the new workflow
	t := ma.WorkflowsLibrary.GetWorkflowTemplateByVersion(ctx, codeqlRepo.RepositoryID, codeqlConfig.TemplateVersion)
	wf, err := t.CodeQLWorkflow(codeqlConfig)
	if err != nil {
		return err
	}
	codeqlConfig.Workflow = wf

	return ma.DataService.ReplaceCodeqlConfigInplace(ctx, codeqlConfig)
}

func (ma *ManagedAnalyses) usesCurrentWorkflowVersion(ctx context.Context, codeqlRepo *ts.CodeqlRepo) bool {
	return ma.WorkflowsLibrary.GetVersion(ctx, codeqlRepo.RepositoryID) == codeqlRepo.CurrentConfig.TemplateVersion
}

func onlyRunnerLabelUpdated(newConfig, old ts.CodeqlConfig) bool {
	old.RunnerLabel = newConfig.RunnerLabel
	old.UsingCSRunnerLabel = newConfig.UsingCSRunnerLabel
	return old.IsEquivalent(&newConfig)
}

func (ma *ManagedAnalyses) triggerCodeqlConfigUpdate(
	ctx context.Context,
	repoID ts.RepositoryEID,
	updatedConfig *ts.CodeqlConfig,
	triggeringEvent ts.CodeqlRunTriggeringEvent,
	// Data needed for validation run:
	defaultRef ts.Ref,
	ownerID ts.OwnerEID,
	codeqlPacks ts.CodeqlPacks,
) (ts.WorkflowRunEID, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	if len(defaultRef) == 0 {
		return 0, errors.New("default ref must be specified for update")
	}

	// Forcing the FF for the entire job because we do not have the owner information everywhere
	if flipper.HasCodeScanningActionsYml(ctx, ownerID, repoID) {
		ctx = flipper.WithFeatureEnabled(ctx, flipper.CodeScanningActionsYml)
	}
	if flipper.HasCodeScanningPrivateRegistry(ctx, ownerID, repoID) {
		ctx = flipper.WithFeatureEnabled(ctx, flipper.CodeScanningPrivateRegistry)
	}

	wf := ma.WorkflowsLibrary.GetWorkflowTemplate(ctx, repoID)
	run, err := updatedConfig.SetUpForValidationRun(defaultRef, ts.EmptySha, wf, triggeringEvent, ownerID, codeqlPacks)
	if err != nil {
		return 0, errors.Wrap(err, "failed to create validation run")
	}

	err = ma.LaunchApiClient.RunDynamicWorkflow(ctx, run)
	if err != nil {
		return 0, errors.Wrap(err, "failed to trigger dynamic workflow")
	}
	ma_.DynamicWorkflowRunLogAndStats(ctx, updatedConfig, run)

	err = ma.DataService.WithTransaction(func(tx ma_.CodeqlDB) error {
		err = tx.CreateStagedCodeqlConfig(ctx, updatedConfig)
		if err != nil {
			return errors.Wrap(err, "failed to create updated codeql config")
		}

		err = tx.CreateCodeqlRun(ctx, run)
		if err != nil {
			return errors.Wrap(err, "failed to create codeql_run")
		}

		return nil
	})
	if err != nil {
		return 0, err
	}

	return run.WorkflowRunID, nil
}

// Coalesce will return the pointer value if set, or the fallback if nil
func Coalesce[T any](pointer *T, fallback T) T {
	if pointer != nil {
		return *pointer
	}
	return fallback
}
