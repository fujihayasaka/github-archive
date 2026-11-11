package agenticapp

import (
	"context"
	"time"

	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/sweagentd"
	gg "github.com/google/go-github/v75/github"
)

func mintToken(ctx context.Context, ghtwirp githubtwirp.ClientInterface, client *gg.Client, tokenReq sweagentd.AgenticAppMintTokenRequest) (string, time.Time, *gg.Response, error) {
	repoID, err := getRepoID(ctx, ghtwirp, tokenReq)
	if err != nil {
		return "", time.Time{}, nil, err
	}

	inst, resp, err := client.Apps.FindRepositoryInstallationByID(ctx, repoID)
	if err != nil {
		return "", time.Time{}, resp, goerrors.Errorf("failed to find installation for repository ID %d: %w", repoID, err)
	}

	opts := &gg.InstallationTokenOptions{
		RepositoryIDs: []int64{repoID},
	}
	instTkn, resp, err := client.Apps.CreateInstallationToken(ctx, inst.GetID(), opts)
	if err != nil {
		return "", time.Time{}, resp, goerrors.Errorf("failed to create installation token for repository ID %d: %w", repoID, err)
	}

	return instTkn.GetToken(), instTkn.GetExpiresAt().Time, resp, nil
}
