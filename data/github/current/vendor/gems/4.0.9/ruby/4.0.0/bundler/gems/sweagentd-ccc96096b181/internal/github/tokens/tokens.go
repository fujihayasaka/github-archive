// Package tokens provides functions to obtain GitHub tokens for repositories.
package tokens

import (
	"context"
	"fmt"
	"time"

	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/sweagentd"
	twirp "github.com/github/sweagentd/proto/sweagentd/v1"
	gg "github.com/google/go-github/v75/github"
)

// Cache is an interface for caching tokens.
type Cache interface {
	Get(key string) (string, error)
	Set(key, token string, expiresAt time.Time) error
}

type globalTokenRequest struct {
	Target        string   `json:"target,omitempty"`
	TargetID      int64    `json:"target_id,omitempty"`
	RepositoryIDs []int64  `json:"repository_ids,omitempty"`
	Repositories  []string `json:"repositories,omitempty"`
}

type globalTokenResponse struct {
	Token      string `json:"token"`
	ExpiresAt  string `json:"expires_at"`
	ValidAfter string `json:"valid_after"`
}

type clientFactory interface {
	NewAppClient(sweagentd.AgenticApp) *gg.Client
}

// GetGlobalTokenByRepo fetches a global token for the given repository.
func GetGlobalTokenByRepo(ctx context.Context, target sweagentd.ClientTarget, cf clientFactory, app sweagentd.AgenticApp, repo sweagentd.Repository, cache Cache, useCache bool) (*gg.Response, string, error) {
	req := globalTokenRequest{
		TargetID:      repo.GetOwnerID(),
		RepositoryIDs: []int64{repo.GetRepositoryID()},
	}

	return getGlobalToken(ctx, target, cf, app, req, cache, useCache)
}

// GetGlobalTokenByRepoID fetches a global token for the given repository ID and owner ID.
func GetGlobalTokenByRepoID(ctx context.Context, target sweagentd.ClientTarget, cf clientFactory, app sweagentd.AgenticApp, repoID, repoOwnerID int64, cache Cache, useCache bool) (*gg.Response, string, error) {
	req := globalTokenRequest{
		TargetID:      repoOwnerID,
		RepositoryIDs: []int64{repoID},
	}

	return getGlobalToken(ctx, target, cf, app, req, cache, useCache)
}

// GetGlobalTokenByRepoName fetches a global token for the given repository name and owner name.
func GetGlobalTokenByRepoName(ctx context.Context, target sweagentd.ClientTarget, cf clientFactory, app sweagentd.AgenticApp, repoName, ownerName string, cache Cache, useCache bool) (*gg.Response, string, error) {
	req := globalTokenRequest{
		Target:       ownerName,
		Repositories: []string{repoName},
	}

	return getGlobalToken(ctx, target, cf, app, req, cache, useCache)
}

func getGlobalToken(ctx context.Context, target sweagentd.ClientTarget, cf clientFactory, app sweagentd.AgenticApp, tokenReq globalTokenRequest, cache Cache, useCache bool) (*gg.Response, string, error) {
	cacheKey := makeGlobalTokenCacheKey(target, tokenReq)
	if useCache {
		if cacheKey != "" {
			cached, err := cache.Get(cacheKey)
			if err == nil && cached != "" {
				return nil, cached, nil
			}
		}
	} else {
		cached := getGlobalTokenFromContext(ctx, target, tokenReq)
		if cached != nil && cached.Token != "" {
			return nil, cached.Token, nil
		}
	}

	client := cf.NewAppClient(app)
	if client == nil {
		return nil, "", goerrors.New("failed to create app client")
	}

	req := sweagentd.AgenticAppMintTokenRequest{
		Target:        tokenReq.Target,
		TargetID:      tokenReq.TargetID,
		RepositoryIDs: tokenReq.RepositoryIDs,
		Repositories:  tokenReq.Repositories,
	}
	mintedToken, expiresAt, resp, err := app.MintToken(ctx, client, req)
	if err != nil {
		return nil, "", goerrors.Errorf("failed to mint token: %w", err)
	}

	if useCache {
		if cacheKey != "" {
			_ = cache.Set(cacheKey, mintedToken, expiresAt)
		}
	} else {
		setGlobalTokenInContext(ctx, target, tokenReq, mintedToken)
	}

	return resp, mintedToken, nil
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
