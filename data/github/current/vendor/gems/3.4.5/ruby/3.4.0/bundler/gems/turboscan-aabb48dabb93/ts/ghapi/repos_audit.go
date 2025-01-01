package ghapi

import (
	"context"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/turboscan/ts"
)

type RepoAuditsResponse struct {
	Results []RepoAudit
}

type RepoAudit struct {
	RepositoryID ts.RepositoryEID `json:"repository_id"`
	Result       string
}

type RepoAuditsRequest struct {
	RepositoryIDs []ts.RepositoryEID `json:"repository_ids"`
}

const (
	// route for the internal endpoint implemented here: https://github.com/github/github/blob/master/app/api/internal/repositories.rb
	reposAuditsRoute = "/repositories/audits"
	// The 'not_found' result is returned from the Dotcom /repositories/audits endpoint when the repository is deleted (or did not exist).
	RepoNotFound = "not_found"
)

type ReposAuditsGetter interface {
	GetReposAudits(ctx context.Context, reqData RepoAuditsRequest) (RepoAuditsResponse, error)
}

// GetReposAudits returns information on whether a repo still exists in github/github
func (c *Client) GetReposAudits(ctx context.Context, reqData RepoAuditsRequest) (RepoAuditsResponse, error) {
	var err error
	startTime := time.Now()
	defer func() {
		c.stats.DistributionMs("repos_audits.get_repositories_audits", nil, time.Since(startTime))
		c.logger.WithError(err).Info("GetReposAudits request",
			kvp.Float64("gh.operation.duration", float64(time.Since(startTime))),
			kvp.Int("gh.turboscan.repo.count", len(reqData.RepositoryIDs)),
		)
	}()
	var respData RepoAuditsResponse
	err = c.sendPostRequestInternal(ctx, reposAuditsRoute, reqData, &respData)
	if err != nil {
		return respData, err
	}

	c.logger.Info("GetReposAudits completed",
		kvp.Int("gh.turboscan.req_count", len(reqData.RepositoryIDs)),
		kvp.Int("gh.turboscan.resp_count", len(respData.Results)),
	)
	return respData, err
}
