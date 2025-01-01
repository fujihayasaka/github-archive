package managedanalyses

import (
	"context"
	"time"

	"github.com/github/turboscan/ts/appctx"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/transforms"
	"github.com/pkg/errors"
)

type ConversionObserver struct {
	getRepositoriesDisabledBetween func(ctx context.Context, t1 time.Time, t2 time.Time) ([]ts.DisabledCodeqlRepo, error)
	getLatestCodeqlYMLAnalyses     func(ctx context.Context, repoID ts.RepositoryEID) ([]*ts.Analysis, error)
	fetchFile                      FetchFileFunc
}

type FetchFileFunc func(ctx context.Context, repoID ts.RepositoryEID, path string, sha ts.Sha) ([]byte, error)

func NewConversionObserver(getRepositoriesDisabledBetween func(ctx context.Context, t1 time.Time, t2 time.Time) ([]ts.DisabledCodeqlRepo, error), getLatestCodeqlYMLAnalyses func(ctx context.Context, repoID ts.RepositoryEID) ([]*ts.Analysis, error), fetchFile FetchFileFunc) *ConversionObserver {
	return &ConversionObserver{
		getRepositoriesDisabledBetween: getRepositoriesDisabledBetween,
		getLatestCodeqlYMLAnalyses:     getLatestCodeqlYMLAnalyses,
		fetchFile:                      fetchFile,
	}
}

// ObserveConversionBetween logs information about repos that disabled managed analyses between t1 and t2
func (co *ConversionObserver) ObserveConversionBetween(ctx context.Context, t1 time.Time, t2 time.Time) error {
	disabledRepos, err := co.getRepositoriesDisabledBetween(ctx, t1, t2)
	if err != nil {
		return errors.Wrap(err, "failed to get disabled repos")
	}

	for _, r := range disabledRepos {
		err := co.observeConversionOf(ctx, r)
		if err != nil {
			return errors.Wrap(err, "failed to get conversion information")
		}
	}

	return nil
}

// ObserveConversionOf logs information about the (potential) conversion of a disabled codeql repo
func (co *ConversionObserver) observeConversionOf(ctx context.Context, repo ts.DisabledCodeqlRepo) error {
	analyses, err := co.getLatestCodeqlYMLAnalyses(ctx, repo.RepositoryID)
	if err != nil {
		return errors.Wrap(err, "failed to get the latest advanced setup analyses")
	}

	// If an analysis was created before disabling default setup it is not a conversion
	analyses = transforms.Filter(analyses, func(a *ts.Analysis) bool {
		return a.CreatedAt.Time.After(repo.DisabledAt.Time)
	})

	if len(analyses) == 0 {
		appctx.Logger(ctx).Info("repo didn't try to convert to advanced setup",
			repo.RepositoryID.AsKVP(),
			kvp.String("gh.turboscan.conversion_observer.status", "no_conversion"),
		)
		return nil
	}

	for _, analysis := range analyses {
		workflow, err := co.fetchFile(ctx, analysis.RepositoryID, analysis.WorkflowPath.String(), analysis.CommitOid)
		if err != nil {
			// We only log the error but ignore it, so we can still log the conversion result even if it is missing the workflow file
			appctx.Logger(ctx).WithError(err).Error(
				"failed to get the workflow file", analysis.RepositoryID.AsKVP(),
				kvp.String("gh.turboscan.conversion_observer.workflow_path", analysis.WorkflowPath.String()),
				kvp.String("gh.turboscan.conversion_observer.commit_oid", analysis.CommitOid.String()),
			)
		}

		appctx.Logger(ctx).Info("conversion observed for repo",
			analysis.RepositoryID.AsKVP(),
			kvp.String("gh.turboscan.conversion_observer.status", analysis.Status().String()),
			kvp.String("gh.turboscan.conversion_observer.category", analysis.Category.String()),
			kvp.String("gh.turboscan.conversion_observer.workflow_path", analysis.WorkflowPath.String()),
			kvp.String("gh.turboscan.conversion_observer.workflow", string(workflow)),
		)
	}
	return nil
}

// FetchFileWithCache adds an in-memory cache to the given FetchFileFunc.
// Note: The implementation uses a very naive caching mechanism that only makes sense within a cronjob
// as a short-lived process.
func FetchFileWithCache(baseFn FetchFileFunc) FetchFileFunc {
	type key struct {
		repoID ts.RepositoryEID
		path   string
		sha    ts.Sha
	}
	cache := make(map[key][]byte)

	fetchFile := func(ctx context.Context, repoID ts.RepositoryEID, path string, sha ts.Sha) ([]byte, error) {
		key := key{
			repoID: repoID,
			path:   path,
			sha:    sha,
		}
		file, ok := cache[key]
		if ok {
			return file, nil
		}

		file, err := baseFn(ctx, repoID, path, sha)
		if err != nil {
			return nil, err
		}
		cache[key] = file
		return file, nil
	}

	return fetchFile
}
