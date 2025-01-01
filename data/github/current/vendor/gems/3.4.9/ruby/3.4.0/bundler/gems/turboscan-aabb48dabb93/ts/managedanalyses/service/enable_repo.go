package managedanalyses

import (
	"context"

	"github.com/github/turboscan/ts"
	"github.com/pkg/errors"
)

// EnableRepo enables managed analyses for a repository
// This involves creating a CodeqlRepo,
// and triggering a validation run if needed,
// by sending a CodeQLRun to Actions' Dynamic Workflows API.
// It returns the WorkflowRunID of the validation run that was triggered.
func (ma *ManagedAnalyses) EnableRepo(
	ctx context.Context,
	repoID ts.RepositoryEID,
	supportedLanguages ts.Languages,
	selectedLanguages ts.Languages,
	querySuite ts.QuerySuite,
	threatModel ts.ThreatModel,
	enabledByActor *ts.ActorGRIDLogin,
	repositoryGRID ts.RepositoryGRID,
	defaultRef ts.Ref,
	ownerID ts.OwnerEID,
	runnerLabel string,
	javaExtractionOptions ts.JavaExtractionOptions,
	csharpExtractionOptions ts.CSharpExtractionOptions,
	cppExtractionOptions ts.CppExtractionOptions,
	codeqlPacks ts.CodeqlPacks,
) (ts.WorkflowRunEID, error) {

	codeqlRepo, err := ma.DataService.GetCodeqlRepo(ctx, repoID)
	if err != nil && !errors.Is(err, ts.ErrCodeqlRepoNotFound) {
		return 0, errors.Wrap(err, "failed to get repository configuration")
	}
	// If it is already enabled we should not try to reenable
	if codeqlRepo != nil {
		return 0, ts.ErrNoChangeRequired
	}

	// Enable managed analyses for repo
	codeqlRepo = &ts.CodeqlRepo{
		RepositoryID:            repoID,
		RepositoryGRID:          repositoryGRID,
		SupportedLanguages:      supportedLanguages,
		QuerySuite:              querySuite,
		ThreatModel:             threatModel,
		JavaExtractionOptions:   javaExtractionOptions,
		CSharpExtractionOptions: csharpExtractionOptions,
		CppExtractionOptions:    cppExtractionOptions,
		EnabledByActorLogin:     enabledByActor.Login,
		RunnerLabel:             runnerLabel,
	}
	err = ma.DataService.CreateCodeqlRepo(ctx, codeqlRepo)
	if err != nil {
		return 0, errors.Wrap(err, "failed to save repository data")
	}

	ma.EnabledStatusService.PublishStatusForDefaultSetup(ctx, repoID, ts.EnablementReason_ENABLE_DEFAULT_SETUP)

	// If there are no selected languages we cannot try to onboard the repo, so we are done
	if len(selectedLanguages) == 0 {
		return 0, nil
	}

	validationRunID, err := ma.OnboardRepo(ctx, repoID, selectedLanguages, querySuite, threatModel, enabledByActor, defaultRef, ownerID, codeqlPacks, runnerLabel)
	if err != nil {
		if errors.Is(err, ts.ErrNoChangeRequired) {
			return 0, errors.New("repo was already onboarded when enabling default setup")
		}
		return 0, errors.Wrap(err, "failed to trigger onboarding")
	}
	return validationRunID, nil
}
