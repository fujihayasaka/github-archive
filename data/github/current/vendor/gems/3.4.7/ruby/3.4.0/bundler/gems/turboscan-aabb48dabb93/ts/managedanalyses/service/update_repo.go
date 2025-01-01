package managedanalyses

import (
	"context"

	"github.com/aws/smithy-go/ptr"

	"github.com/github/turboscan/ts"
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
	runnerLabel *string,
) (ts.WorkflowRunEID, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	codeqlRepo, err := ma.DataService.GetCodeqlRepo(ctx, repoID)
	if err != nil {
		return 0, err
	}

	if runnerLabel == nil {
		// Preserve runner label settings if the update specifies to keep it
		runnerLabel = ptr.String(codeqlRepo.RunnerLabel)
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
		*runnerLabel,
	)
}
