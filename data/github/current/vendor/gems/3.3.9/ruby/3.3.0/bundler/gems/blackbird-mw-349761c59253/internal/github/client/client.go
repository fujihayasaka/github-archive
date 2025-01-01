package client

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"

	"github.com/cenkalti/backoff/v4"
	"github.com/github/go-auth/hmac"
	"github.com/github/go-http/middleware/headers"
	"github.com/github/go-stats"
	"github.com/github/go-telemetry/statting"
	gh "github.com/google/go-github/github"

	"github.com/github/blackbird-mw/internal/github"
	"github.com/github/blackbird-mw/internal/retry"
	"github.com/github/blackbird-mw/internal/types"
)

type InternalAPIHttpClient struct {
	baseURL      string
	hmacSecret   string
	githubClient *gh.Client
	token        string // token for the public github api
}

const (
	getRepoURL = "internal/blackbird/repositories"
	getUserURL = "internal/blackbird/users"
)

func NewInternalAPIClient(httpClient *http.Client, baseURL, hmacSecret string, token string) *InternalAPIHttpClient {
	return &InternalAPIHttpClient{strings.TrimSuffix(baseURL, "/"), hmacSecret, gh.NewClient(httpClient), token}
}

func (i *InternalAPIHttpClient) GetRepositoryByNWO(ctx context.Context, nwo types.NWO) (*github.Repository, error) {
	return i.getRepository(ctx, fmt.Sprintf("%s/%s/%s", i.baseURL, getRepoURL, nwo.String()))
}

func (i *InternalAPIHttpClient) GetRepository(ctx context.Context, repoID types.RepoID) (*github.Repository, error) {
	start := time.Now()
	repo, err := i.getRepository(ctx, fmt.Sprintf("%s/%s/%d", i.baseURL, getRepoURL, repoID))
	if err != nil {
		statting.DistributionMs(ctx, "github.get_repository.duration", time.Since(start), stats.Tags{"status": "error"})
		return nil, err
	}

	statting.DistributionMs(ctx, "github.get_repository.duration", time.Since(start), stats.Tags{"status": "success"})
	return repo, nil
}

func (i *InternalAPIHttpClient) getRepository(ctx context.Context, url string) (*github.Repository, error) {
	request, err := http.NewRequestWithContext(ctx, "GET", url, nil)
	request.Header.Add(headers.RequestHMAC, hmac.NewRequestHMAC(i.hmacSecret).String())
	if err != nil {
		return nil, fmt.Errorf("failed create GetRepository request: %w", err)
	}

	var repo *github.Repository
	response, err := i.githubClient.Do(ctx, request, &repo)
	if err != nil {
		if response != nil {
			switch response.StatusCode {
			case http.StatusNotFound:
				return nil, github.ErrRepoNotFound
			case http.StatusForbidden:
				return nil, github.ErrRepoDisabled
			case http.StatusUnavailableForLegalReasons:
				return nil, github.ErrRepoBlocked
			default:
				return nil, err
			}
		}
		return nil, err
	}

	return repo, nil
}

func (i *InternalAPIHttpClient) GetUser(ctx context.Context, login string) (*gh.User, error) {
	request, err := http.NewRequestWithContext(ctx, "GET", fmt.Sprintf("%s/%s/%s", i.baseURL, getUserURL, url.PathEscape(login)), nil)
	request.Header.Add(headers.RequestHMAC, hmac.NewRequestHMAC(i.hmacSecret).String())
	if err != nil {
		return nil, err
	}
	var user *gh.User
	_, err = i.githubClient.Do(ctx, request, &user)
	return user, err
}

func (i *InternalAPIHttpClient) GetRepositoriesByIds(ctx context.Context, repoIDs []types.RepoID) ([]*github.Repository, error) {
	type getRepositoriesByIDs struct {
		RepositoryIDs []types.RepoID `json:"repository_ids"`
	}

	requestBody := getRepositoriesByIDs{
		RepositoryIDs: repoIDs,
	}

	jsonBody, err := json.Marshal(requestBody)
	if err != nil {
		return nil, err
	}

	repos, _, err := i.getRepositories(ctx, bytes.NewBuffer(jsonBody))
	return repos, err
}

func (i *InternalAPIHttpClient) GetRepositoriesByCursor(ctx context.Context, cursor string, limit int) ([]*github.Repository, string, error) {
	type getRepositoriesByCursor struct {
		Cursor string `json:"cursor"`
		Limit  int    `json:"limit"`
	}

	requestBody := getRepositoriesByCursor{
		Cursor: cursor,
		Limit:  limit,
	}

	jsonBody, err := json.Marshal(requestBody)
	if err != nil {
		return nil, "", err
	}

	return i.getRepositories(ctx, bytes.NewBuffer(jsonBody))
}

func (i *InternalAPIHttpClient) getRepositories(ctx context.Context, requestBody io.Reader) ([]*github.Repository, string, error) {
	type response struct {
		Repositories []*github.Repository `json:"repositories"`
		NextCursor   string               `json:"next_cursor"`
	}

	resp := &response{}
	attempt := 0
	operation := func() error {
		attempt++

		request, err := http.NewRequestWithContext(ctx, "POST", fmt.Sprintf("%s/%s", i.baseURL, getRepoURL), requestBody)
		request.Header.Add(headers.RequestHMAC, hmac.NewRequestHMAC(i.hmacSecret).String())
		if err != nil {
			return backoff.Permanent(fmt.Errorf("failed to create GetRepositoriesByCursor request: %w", err))
		}

		response, err := i.githubClient.Do(ctx, request, resp)
		if err != nil {
			if response != nil {
				return retry.CheckHTTPResponse(response.Response, err)
			}
			return backoff.Permanent(err)
		}
		return nil
	}

	const numRetries = uint64(3)
	err := backoff.Retry(operation, retry.DefaultBackOff(ctx, numRetries))
	if err != nil {
		return nil, "", err
	}
	return resp.Repositories, resp.NextCursor, nil
}

func (i *InternalAPIHttpClient) GetPullsForCommit(ctx context.Context, nwo types.NWO, commitSHA string) ([]*gh.PullRequest, error) {
	var pulls []*gh.PullRequest
	request, err := http.NewRequestWithContext(ctx, "GET", fmt.Sprintf("%s/repos/%s/commits/%s/pulls", i.baseURL, nwo.String(), commitSHA), nil)
	request.Header.Add("Authorization", fmt.Sprintf("Bearer %s", i.token))
	if err != nil {
		return nil, fmt.Errorf("failed create GetPullsForCommit request: %w", err)
	}

	_, err = i.githubClient.Do(ctx, request, &pulls)
	if err != nil {
		return nil, fmt.Errorf("failed to get pull requests for commit %q: %w", commitSHA, err)
	}
	return pulls, nil
}
