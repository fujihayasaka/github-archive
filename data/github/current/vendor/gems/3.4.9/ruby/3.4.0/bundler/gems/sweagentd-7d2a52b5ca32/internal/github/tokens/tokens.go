package tokens

import (
	"context"
	"errors"
	"fmt"

	"github.com/github/sweagentd/internal/sweagentd"
	twirp "github.com/github/sweagentd/proto/sweagentd/v1"
	gg "github.com/google/go-github/v75/github"
)

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
	NewAppClient() *gg.Client
}

// GetGlobalTokenByRepo fetches a global token for the given repository.
func GetGlobalTokenByRepo(ctx context.Context, cf clientFactory, repo sweagentd.Repository) (*gg.Response, string, error) {
	req := globalTokenRequest{
		TargetID:      repo.GetOwnerID(),
		RepositoryIDs: []int64{repo.GetRepositoryID()},
	}
	return getGlobalToken(ctx, cf, req)
}

// GetGlobalTokenByRepoID fetches a global token for the given repository ID and owner ID.
func GetGlobalTokenByRepoID(ctx context.Context, cf clientFactory, repoID, repoOwnerID int64) (*gg.Response, string, error) {
	req := globalTokenRequest{
		TargetID:      repoOwnerID,
		RepositoryIDs: []int64{repoID},
	}
	return getGlobalToken(ctx, cf, req)
}

// GetGlobalTokenByRepoName fetches a global token for the given repository name and owner name.
func GetGlobalTokenByRepoName(ctx context.Context, cf clientFactory, repoName, ownerName string) (*gg.Response, string, error) {
	req := globalTokenRequest{
		Target:       ownerName,
		Repositories: []string{repoName},
	}
	return getGlobalToken(ctx, cf, req)
}

func getGlobalToken(ctx context.Context, cf clientFactory, tokenReq globalTokenRequest) (*gg.Response, string, error) {
	cached := getGlobalTokenFromContext(ctx, tokenReq)
	if cached != nil && cached.Token != "" {
		return nil, cached.Token, nil
	}

	client := cf.NewAppClient()
	if client == nil {
		return nil, "", errors.New("failed to create app client")
	}

	tokenRes := &globalTokenResponse{}
	req, err := client.NewRequest("POST", "/app/global/access_tokens", tokenReq)
	if err != nil {
		return nil, "", err
	}
	resp, err := client.Do(ctx, req, tokenRes)
	if err != nil {
		return resp, "", fmt.Errorf("failed to create global app token: %w", err)
	}
	if tokenRes.Token == "" {
		return resp, "", errors.New("failed to create global app token: empty token")
	}

	setGlobalTokenInContext(ctx, tokenReq, tokenRes)

	return resp, tokenRes.Token, nil
}

type userTokenMinter interface {
	MintUserToServerTokenForRepo(context.Context, *twirp.MintUserToServerTokenForRepoRequest) (*twirp.MintUserToServerTokenForRepoResponse, error)
}

// GetUserToServerToken fetches a user-to-server token for the given user ID and repository ID.
func GetUserToServerToken(ctx context.Context, minter userTokenMinter, ids sweagentd.ActorWithRepository) (string, error) {
	userID := ids.GetActorID()
	repoID := ids.GetRepositoryID()

	cached := getUserTokenFromContext(ctx, userID, repoID)
	if cached != nil && cached.Token != "" {
		return cached.Token, nil
	}

	response, err := minter.MintUserToServerTokenForRepo(ctx, &twirp.MintUserToServerTokenForRepoRequest{
		UserId:       uint64(userID),
		RepositoryId: uint64(repoID),
	})

	if err != nil {
		return "", fmt.Errorf("failed to mint user to server token for repo: %w", err)
	}

	if response == nil || response.Token == "" {
		return "", errors.New("failed to mint user to server token for repo. token is invalid or empty")
	}

	setUserTokenInContext(ctx, userID, repoID, response.Token)

	return response.Token, nil
}
