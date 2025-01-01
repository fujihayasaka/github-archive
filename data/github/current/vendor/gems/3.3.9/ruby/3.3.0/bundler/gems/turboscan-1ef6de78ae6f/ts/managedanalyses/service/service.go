// Package managedanalyses contains the main logic for Managed Analyses
package managedanalyses

import (
	"context"
	"time"

	tshydro "github.com/github/hydro-schemas-go/hydro/schemas/code_scanning/v0"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/ghapi"

	ma_ "github.com/github/turboscan/ts/managedanalyses"
	"github.com/github/turboscan/ts/twirp/clients/actions"
	"github.com/github/turboscan/ts/twirp/clients/ghgh"
	"github.com/github/turboscan/ts/workflows"
)

// ManagedAnalyses contains the logic associated with Managed Analyses.
type ManagedAnalyses struct {
	DataService          ma_.CodeqlDB
	LaunchApiClient      actions.DynamicWorkflowRunner
	GitHubTwirpApiClient ghgh.ManagedAnalysesAPI
	GitHubApiClient      ghapi.WorkflowRunAnnotationsGetter
	EnabledStatusService ma_.StatusService

	GetBotActor        func(ctx context.Context) (*ts.ActorGRIDLogin, error)
	UpdateRepoMetadata ma_.UpdateRepoMetadataFn
	WorkflowsLibrary   *workflows.Library

	Scheduler *ma_.Scheduler

	// DormantRepoDays is the number of days after which a repository is considered dormant
	// and won't be scheduled for analysis. If nil, a repo is never considered dormant.
	DormantRepoDays *int

	HydroPublisher ManagedAnalysesHydroPublisher
}

type ManagedAnalysesHydroPublisher interface {
	WorkflowRunAnnotationsBatch(context.Context, []*tshydro.WorkflowRunAnnotation) error
}

func (ma *ManagedAnalyses) areReposActive(ctx context.Context, repoIDs []ts.RepositoryEID) (map[ts.RepositoryEID]bool, error) {
	if ma.DormantRepoDays == nil {
		// Consider all repos as active
		activeRepos := make(map[ts.RepositoryEID]bool, len(repoIDs))
		for _, repoID := range repoIDs {
			activeRepos[repoID] = true
		}
		return activeRepos, nil
	}
	deadline := time.Now().AddDate(0, 0, -(*ma.DormantRepoDays))
	return ma.DataService.HadNonScheduledRunsAfter(ctx, repoIDs, deadline)
}
