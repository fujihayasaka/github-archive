// Package tokens provides functions to obtain GitHub tokens for repositories.
package tokens

import (
	"context"
	"fmt"
	"time"

	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/sweagentd"
	twirp "github.com/github/sweagentd/proto/sweagentd/v1"
)

// defaultTokenTTL is the default TTL for cached tokens when expires_at is not
// available from the server-to-server response. GitHub tokens expire after 1 hour
// by default; we use 55 minutes to provide a safety margin.
const defaultTokenTTL = 55 * time.Minute

// Cache is an interface for caching tokens.
type Cache interface {
	Get(key string) (string, error)
	Set(key, token string, expiresAt time.Time) error
	Delete(key string) error
}

type globalTokenRequest struct {
	Target        string
	TargetID      int64
	RepositoryIDs []int64
	Repositories  []string
}

// serverTokenMinter is the minimal interface for minting server-to-server tokens.
type serverTokenMinter interface {
	MintServerToServerTokenForRepo(context.Context, *twirp.MintServerToServerTokenForRepoRequest) (*twirp.MintServerToServerTokenForRepoResponse, error)
}

type userTokenMinter interface {
	MintUserToServerTokenForRepo(context.Context, *twirp.MintUserToServerTokenForRepoRequest) (*twirp.MintUserToServerTokenForRepoResponse, error)
}

// GetUserToServerToken fetches a user-to-server token for the given user ID and repository ID.
func GetUserToServerToken(ctx context.Context, target sweagentd.ClientTarget, agentID int64, minter userTokenMinter, ids sweagentd.ActorWithRepository) (string, error) {
	userID := ids.GetActorID()
	repoID := ids.GetRepositoryID()
	cached := getUserTokenFromContext(ctx, target, repoID)
	if cached != nil && cached.Token != "" {
		return cached.Token, nil
	}

	// TODO(josebalius): assumes sweagentd has been generalized
	req := &twirp.MintUserToServerTokenForRepoRequest{
		UserId:       uint64(userID),
		RepositoryId: uint64(repoID),
		AgentId:      agentID,
	}
	response, err := minter.MintUserToServerTokenForRepo(ctx, req)
	if err != nil {
		return "", goerrors.Errorf("failed to mint user to server token for repo: %w", err)
	}
	if response == nil || response.Token == "" {
		return "", goerrors.New("failed to mint user to server token for repo. token is invalid or empty")
	}
	setUserTokenInContext(ctx, target, repoID, response.Token)

	return response.Token, nil
}

// OrgBillableJob is the minimal interface a job must satisfy for org billing token selection.
type OrgBillableJob interface {
	sweagentd.ActorWithRepository
	IsBillToOrg() bool
	GetOwnerID() int64
}

// GetTokenForJob returns the appropriate CAPI token for the job's billing mode.
// For org-billed jobs (IsBillToOrg=true), it mints an org-scoped S2S token so
// CAPI routes billing to the org's seat pool via its existing TypeOrg actor path.
// For user-billed jobs, it delegates to GetUserToServerToken.
func GetTokenForJob(ctx context.Context, target sweagentd.ClientTarget, agentID int64, userMinter userTokenMinter, s2sMinter serverTokenMinter, app sweagentd.AgenticApp, job OrgBillableJob, cache Cache) (string, error) {
	if job.IsBillToOrg() {
		return GetServerToServerTokenByRepo(ctx, target, s2sMinter, app, job, cache)
	}
	return GetUserToServerToken(ctx, target, agentID, userMinter, job)
}

// makeGlobalTokenCacheKey references internal/github/tokens/context.go in its key definition.
func makeGlobalTokenCacheKey(target sweagentd.ClientTarget, req globalTokenRequest) string {
	switch {
	case req.TargetID != 0 && len(req.RepositoryIDs) == 1:
		return fmt.Sprintf("target:%s:repo_id:%d", target.Key(), req.RepositoryIDs[0])
	case req.Target != "" && len(req.Repositories) == 1:
		return fmt.Sprintf("target:%s:repo_name:%s", target.Key(), req.Repositories[0])
	default:
		return ""
	}
}

// GlobalCacheKeyForRepo returns the cache key used for a server-to-server token
// for the given target, repo ID, and owner ID. Returns "" if the inputs are
// incomplete. This is exported so that callers (e.g., the token refresh
// coordinator) can use the same key without duplicating the logic.
func GlobalCacheKeyForRepo(target sweagentd.ClientTarget, repoID, repoOwnerID int64) string {
	return makeGlobalTokenCacheKey(target, globalTokenRequest{
		TargetID:      repoOwnerID,
		RepositoryIDs: []int64{repoID},
	})
}

// NoopCache is a noop implementation of Cache for testing.
type NoopCache struct{}

// Get always returns an empty string and no error.
func (c *NoopCache) Get(key string) (string, error) {
	return "", nil
}

// Set does nothing and returns no error.
func (c *NoopCache) Set(key, token string, expiresAt time.Time) error {
	return nil
}

// Delete does nothing and returns no error.
func (c *NoopCache) Delete(key string) error {
	return nil
}

// GetServerToServerTokenByRepo fetches a server-to-server token for the given repository.
func GetServerToServerTokenByRepo(ctx context.Context, target sweagentd.ClientTarget, minter serverTokenMinter, app sweagentd.AgenticApp, repo sweagentd.Repository, cache Cache) (string, error) {
	req := globalTokenRequest{
		TargetID:      repo.GetOwnerID(),
		RepositoryIDs: []int64{repo.GetRepositoryID()},
	}

	return getServerToServerToken(ctx, target, minter, app, repo.GetRepositoryID(), req, cache)
}

// GetServerToServerTokenByRepoID fetches a server-to-server token for the given repository ID and owner ID.
func GetServerToServerTokenByRepoID(ctx context.Context, target sweagentd.ClientTarget, minter serverTokenMinter, app sweagentd.AgenticApp, repoID, repoOwnerID int64, cache Cache) (string, error) {
	req := globalTokenRequest{
		TargetID:      repoOwnerID,
		RepositoryIDs: []int64{repoID},
	}

	return getServerToServerToken(ctx, target, minter, app, repoID, req, cache)
}

func getServerToServerToken(ctx context.Context, target sweagentd.ClientTarget, minter serverTokenMinter, app sweagentd.AgenticApp, repoID int64, tokenReq globalTokenRequest, cache Cache) (string, error) {
	cacheKey := makeGlobalTokenCacheKey(target, tokenReq)
	if cacheKey != "" {
		cached, err := cache.Get(cacheKey)
		if err == nil && cached != "" {
			return cached, nil
		}
	}

	mintedToken, err := mintServerToServerToken(ctx, minter, app, repoID)
	if err != nil {
		return "", err
	}

	if cacheKey != "" {
		_ = cache.Set(cacheKey, mintedToken, time.Now().Add(defaultTokenTTL))
	}

	return mintedToken, nil
}

func mintServerToServerToken(ctx context.Context, minter serverTokenMinter, app sweagentd.AgenticApp, repoID int64) (string, error) {
	req := &twirp.MintServerToServerTokenForRepoRequest{
		RepositoryId: uint64(repoID),
		AgentId:      app.AppID(),
	}

	resp, err := minter.MintServerToServerTokenForRepo(ctx, req)
	if err != nil {
		return "", goerrors.Errorf("failed to mint server-to-server token: %w", err)
	}
	if resp == nil || resp.Token == "" {
		return "", goerrors.Errorf("failed to mint server-to-server token for repo %d: empty token", repoID)
	}

	return resp.Token, nil
}

// InvalidateServerToServerTokenForRepo evicts the cached S2S token for the
// given app installation and repository. This should be called when a 401
// indicates the cached token has been revoked (e.g. after an app reinstall).
func InvalidateServerToServerTokenForRepo(target sweagentd.ClientTarget, repoID, repoOwnerID int64, cache Cache) {
	req := globalTokenRequest{
		TargetID:      repoOwnerID,
		RepositoryIDs: []int64{repoID},
	}
	cacheKey := makeGlobalTokenCacheKey(target, req)
	if cacheKey != "" {
		_ = cache.Delete(cacheKey)
	}
}
