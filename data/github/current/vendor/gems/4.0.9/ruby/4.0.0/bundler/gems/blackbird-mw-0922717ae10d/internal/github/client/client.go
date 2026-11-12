package client

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strconv"
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
	getRepoURL                    = "internal/blackbird/repositories"
	getRepoByNWOURL               = "internal/blackbird/repos"
	getUserURL                    = "internal/blackbird/users"
	copilotIndexedRepositoriesURL = "internal/blackbird/copilot_indexed_repositories"
)

func NewInternalAPIClient(httpClient *http.Client, baseURL, hmacSecret string, token string) *InternalAPIHttpClient {
	return &InternalAPIHttpClient{strings.TrimSuffix(baseURL, "/"), hmacSecret, gh.NewClient(httpClient), token}
}

func (i *InternalAPIHttpClient) RepoURL() string {
	return fmt.Sprintf("%s/%s", i.baseURL, getRepoURL)
}

func (i *InternalAPIHttpClient) BaseUrl() string {
	return i.baseURL
}

func (i *InternalAPIHttpClient) Do(ctx context.Context, req *http.Request, v interface{}) (*gh.Response, error) {
	return i.githubClient.Do(ctx, req, v)
}

func (i *InternalAPIHttpClient) GetRepositoryByNWO(ctx context.Context, nwo types.NWO) (*github.Repository, error) {
	return i.getRepository(ctx, fmt.Sprintf("%s/%s/%s", i.baseURL, getRepoByNWOURL, nwo.String()))
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
	if err != nil {
		return nil, fmt.Errorf("failed create GetRepository request: %w", err)
	}
	request.Header.Add(headers.RequestHMAC, hmac.NewRequestHMAC(i.hmacSecret).String())

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
			case http.StatusServiceUnavailable:
				return nil, github.ErrServiceUnavailable
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
		if err != nil {
			return backoff.Permanent(fmt.Errorf("failed to create GetRepositoriesByCursor request: %w", err))
		}
		request.Header.Add(headers.RequestHMAC, hmac.NewRequestHMAC(i.hmacSecret).String())

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
	if err != nil {
		return nil, fmt.Errorf("failed create GetPullsForCommit request: %w", err)
	}
	request.Header.Add("Authorization", fmt.Sprintf("Bearer %s", i.token))

	_, err = i.githubClient.Do(ctx, request, &pulls)
	if err != nil {
		return nil, fmt.Errorf("failed to get pull requests for commit %q: %w", commitSHA, err)
	}
	return pulls, nil
}

var defaultRecord = &github.CopilotIndexedRepository{}

func (i *InternalAPIHttpClient) GetCopilotIndexedRepositories(ctx context.Context, limit int, startRecord *github.CopilotIndexedRepository) ([]*github.CopilotIndexedRepository, error) {
	type response struct {
		CopilotIndexedRepositories []*github.CopilotIndexedRepository `json:"copilot_indexed_repositories"`
	}

	request, err := http.NewRequestWithContext(ctx, "GET", fmt.Sprintf("%s/%s", i.baseURL, copilotIndexedRepositoriesURL), nil)
	if err != nil {
		return nil, fmt.Errorf("failed create GetCopilotIndexedRepositories request: %w", err)
	}

	// Parse existing query params (if any), add your own.
	q := request.URL.Query()
	q.Add("limit", strconv.Itoa(limit))
	if startRecord != nil && *startRecord != *defaultRecord {
		q.Add("inclusive_start_timestamp", startRecord.LastRequestedAt.String())
		q.Add("exclusive_start_repo_id", strconv.FormatInt(int64(startRecord.RepositoryID), 10))
	}
	request.URL.RawQuery = q.Encode()
	request.Header.Add(headers.RequestHMAC, hmac.NewRequestHMAC(i.hmacSecret).String())

	resp := &response{}
	_, err = i.githubClient.Do(ctx, request, resp)
	if err != nil {
		return nil, fmt.Errorf("failed to get copilot indexed repositories: %w", err)
	}

	return resp.CopilotIndexedRepositories, nil
}

func (i *InternalAPIHttpClient) DeleteCopilotIndexedRepository(ctx context.Context, force bool, cir *github.CopilotIndexedRepository) (int, error) {
	type deleteCopilotIndexedRepository struct {
		Force        bool         `json:"force"`
		RepositoryID types.RepoID `json:"repository_id"`
	}

	requestBody := deleteCopilotIndexedRepository{
		Force:        force,
		RepositoryID: cir.RepositoryID,
	}

	jsonBody, err := json.Marshal(requestBody)
	if err != nil {
		return 0, err
	}

	request, err := http.NewRequestWithContext(ctx, "DELETE", fmt.Sprintf("%s/%s", i.baseURL, copilotIndexedRepositoriesURL), bytes.NewBuffer(jsonBody))
	if err != nil {
		return 0, fmt.Errorf("failed create DeleteCopilotIndexedRepository request: %w", err)
	}
	request.Header.Add(headers.RequestHMAC, hmac.NewRequestHMAC(i.hmacSecret).String())

	resp, err := i.githubClient.Do(ctx, request, nil)
	if err != nil {
		// The github client package returns an ErrorResponse for status code outside the 200 status range, except for 202.
		// This translates those error responses into their respective status codes.
		var errResponse *gh.ErrorResponse
		if errors.As(err, &errResponse) {
			return errResponse.Response.StatusCode, nil
		}
		return 0, fmt.Errorf("failed to delete copilot indexed repository record: %w", err)
	}

	return resp.StatusCode, nil
}

func (i *InternalAPIHttpClient) UpdateCopilotIndexedRepository(ctx context.Context, cir *github.CopilotIndexedRepository) (int, error) {
	type updateCopilotIndexedRepository struct {
		RepositoryID types.RepoID `json:"repository_id"`
	}

	requestBody := updateCopilotIndexedRepository{
		RepositoryID: cir.RepositoryID,
	}

	jsonBody, err := json.Marshal(requestBody)
	if err != nil {
		return 0, err
	}

	request, err := http.NewRequestWithContext(ctx, "POST", fmt.Sprintf("%s/%s", i.baseURL, copilotIndexedRepositoriesURL), bytes.NewBuffer(jsonBody))
	if err != nil {
		return 0, fmt.Errorf("failed create UpdateCopilotIndexedRepository request: %w", err)
	}
	request.Header.Add(headers.RequestHMAC, hmac.NewRequestHMAC(i.hmacSecret).String())

	resp, err := i.githubClient.Do(ctx, request, nil)
	if err != nil {
		// The github client package returns an ErrorResponse for status code outside the 200 status range, except for 202.
		// This translates those error responses into their respective status codes.
		var errResponse *gh.ErrorResponse
		if errors.As(err, &errResponse) {
			return errResponse.Response.StatusCode, nil
		}
		return 0, fmt.Errorf("failed to update copilot indexed repository record: %w", err)
	}

	return resp.StatusCode, nil
}

func (i *InternalAPIHttpClient) IndexEmbeddings(ctx context.Context, repoID types.RepoID, actorID uint32) (int, error) {
	type indexEmbeddingsRequest struct {
		ActorID uint32 `json:"actor_id"`
		Force   bool   `json:"force"`
	}
	url := fmt.Sprintf("%s/%s/%d/embeddings_index", i.baseURL, getRepoURL, repoID)
	requestBody := indexEmbeddingsRequest{
		ActorID: actorID,
		Force:   true,
	}

	jsonBody, err := json.Marshal(requestBody)
	if err != nil {
		return 0, err
	}

	request, err := http.NewRequestWithContext(ctx, "POST", url, bytes.NewBuffer(jsonBody))
	if err != nil {
		return 0, fmt.Errorf("failed to create IndexEmbeddings request: %w", err)
	}
	request.Header.Add(headers.RequestHMAC, hmac.NewRequestHMAC(i.hmacSecret).String())

	resp, err := i.githubClient.Do(ctx, request, nil)
	if err != nil {
		return 0, fmt.Errorf("failed to index repo with embeddings: %w", err)
	}
	statusOk := resp.StatusCode >= 200 && resp.StatusCode < 300
	if !statusOk {
		return resp.StatusCode, fmt.Errorf("failed to index repo with embedding. Received status code: %d", resp.StatusCode)
	}

	return resp.StatusCode, nil
}
