package managedanalyses

import (
	"context"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/flipper"
	"github.com/github/turboscan/ts/o11y"
)

// UpdateRepo updates the CodeqlConfig for a repository and returns the workflow id
// of the last relevant validation run.
// If the new configuration is equivalent to the existing one, it will not trigger a new validation run .
func (ma *ManagedAnalyses) UpdateRepo(
	ctx context.Context,
	repoID ts.RepositoryEID,
	supportedLanguages ts.Languages,
	selectedLanguages *ts.Languages,
	querySuite *ts.QuerySuite,
	threatModel *ts.ThreatModel,
	actor *ts.ActorGRIDLogin,
	defaultRef ts.Ref,
	ownerID ts.OwnerEID,
	codeqlPacks ts.CodeqlPacks,
	useCodeScanningRunnerLabel *bool,
	runnerLabel string,
) (ts.WorkflowRunEID, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	codeqlRepo, err := ma.DataService.GetCodeqlRepo(ctx, repoID)
	if err != nil {
		return 0, err
	}
	var useRunnerLabel bool
	csRunnerLabelEnabled := flipper.HasCodeScanningCustomRunnerLabels(ctx, ownerID, codeqlRepo.RepositoryID)
	if useCodeScanningRunnerLabel == nil || !csRunnerLabelEnabled {
		// Preserve runner label settings if the update specifies to keep it
		runnerLabel = codeqlRepo.RunnerLabel
		useRunnerLabel = codeqlRepo.UsingCSRunnerLabel
	} else {
		useRunnerLabel = *useCodeScanningRunnerLabel
	}
	return ma.updateRepo(
		ctx,
		codeqlRepo,
		ts.CodeqlRunTriggeringEvent_VALIDATION,
		supportedLanguages,
		selectedLanguages,
		querySuite,
		threatModel,
		defaultRef,
		ownerID,
		codeqlPacks,
		actor,
		useRunnerLabel,
		runnerLabel,
	)
}
