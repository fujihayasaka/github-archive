package agenticapp

import (
	"context"
	"errors"
	"fmt"

	repositoriesTwirp "github.com/github/github-proto/gen/go/repositories/v1"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/sweagentd"
	"github.com/twitchtv/twirp"
)

func getRepoID(ctx context.Context, ghtwirp githubtwirp.ClientInterface, tokenReq sweagentd.AgenticAppMintTokenRequest) (int64, error) {
	if len(tokenReq.RepositoryIDs) != 0 {
		return tokenReq.RepositoryIDs[0], nil
	}

	if len(tokenReq.Repositories) != 1 {
		return 0, goerrors.New("exactly one repository identifier required to mint token")
	}

	if tokenReq.Target == "" {
		return 0, goerrors.New("target owner name is required to mint token")
	}

	owner := tokenReq.Target
	repo := tokenReq.Repositories[0]
	req := &repositoriesTwirp.FindRepositoriesByNameRequest{
		Nwos: []string{fmt.Sprintf("%s/%s", owner, repo)},
	}
	resp, err := ghtwirp.RepositoriesAPI().FindRepositoriesByName(ctx, req)
	if err != nil {
		var twirpErr twirp.Error
		if ok := errors.As(err, &twirpErr); ok && twirpErr.Code() == twirp.NotFound {
			return 0, goerrors.New("twirp repository not found")
		}

		return 0, err
	}

	repos := resp.GetRepositories()
	if len(repos) == 0 {
		return 0, goerrors.New("repository not found")
	}

	return repos[0].GetId(), nil
}
