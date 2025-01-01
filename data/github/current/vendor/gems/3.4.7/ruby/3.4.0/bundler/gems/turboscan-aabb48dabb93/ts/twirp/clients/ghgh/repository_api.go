// Package ghgh contains Twirp clients for connecting to github/github.
package ghgh

import (
	"context"
	"time"

	"github.com/github/hydro-schemas-go/hydro/schemas/github/v1/entities"

	"github.com/SamuelTissot/sqltime"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	"github.com/github/turboscan/ts"
	repositories "github.com/github/turboscan/ts/monolith_twirp/repositories/v1"
	"github.com/github/turboscan/ts/o11y"
)

type RepositoryAPI interface {
	// GetRepositories returns the repository metadata for the given repository IDs.
	GetRepositories(ctx context.Context, ids []ts.RepositoryEID) ([]*ts.Repository, error)
}

type repositoryAPI struct {
	client repositories.RepositoriesAPI
	logger log.Logger
	stats  stats.Client
}

// NewRepositoryAPI returns the twirp client for the RepositoryAPI TWIRP service
func NewRepositoryAPI(client repositories.RepositoriesAPI, logger log.Logger, stats stats.Client) RepositoryAPI {
	return &repositoryAPI{
		client: client,
		logger: logger,
		stats:  stats,
	}
}

func (r *repositoryAPI) GetRepositories(ctx context.Context, repoIDs []ts.RepositoryEID) ([]*ts.Repository, error) {
	return r.getRepositories(ctx, repoIDs)
}

// getRepositories queries the TWIRP API for a set of repository ids, and returns ts.Repository objects with the relevant
// security data.
func (r *repositoryAPI) getRepositories(ctx context.Context, repoIDs []ts.RepositoryEID) ([]*ts.Repository, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	var err error
	startTime := time.Now()
	defer func() {
		r.stats.DistributionMs("repository_api.get_repositories", nil, time.Since(startTime))
		r.logger.WithError(err).Info("GetRepositories request",
			kvp.Float64("gh.operation.duration", float64(time.Since(startTime))),
			kvp.Int("gh.turboscan.repo.count", len(repoIDs)),
		)
	}()

	ids := []int64{}
	for _, id := range repoIDs {
		ids = append(ids, int64(id))
	}
	reqTime := sqltime.Now()
	req := &repositories.FindRepositoriesRequest{Ids: ids}
	resp, err := r.client.FindRepositories(ctx, req)
	if err != nil {
		r.stats.Counter("repository_api.error", stats.Tags{"err": "find_repositories"}, 1)
		return nil, err
	}
	repos := []*ts.Repository{}

	for _, repo := range resp.RepositoriesById {
		defaultRef := []byte("")
		if repo.DefaultBranchRef != nil {
			defaultRef = repo.DefaultBranchRef
		}

		v := entities.Repository_Visibility(repo.Visibility)

		out := &ts.Repository{
			RepositoryID:        ts.RepositoryEID(repo.Id),
			OwnerID:             ts.OwnerEID(repo.OrganizationId),
			CodeScanningEnabled: repo.CodeScanningEnabled,
			SourceUpdatedAt:     reqTime,
			DefaultRef:          defaultRef,
			Visibility:          ts.RepositoryVisibilityFromSecurityCenterProto(v),
		}
		repos = append(repos, out)
	}

	return repos, nil
}
