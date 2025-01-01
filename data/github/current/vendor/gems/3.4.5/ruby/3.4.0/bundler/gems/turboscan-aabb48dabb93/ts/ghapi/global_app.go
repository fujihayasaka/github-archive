package ghapi

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"

	"github.com/github/turboscan/ts"
	"github.com/pkg/errors"

	gogh "github.com/google/go-github/v52/github"
)

const (
	GlobalAppAccessRoute = "app/global/access_tokens"
)

type CreateGlobalAccessTokenOptions struct {
	TargetID       int64                         `json:"target_id"`
	RepositoryIDs  []int64                       `json:"repository_ids,omitempty"`
	Repositories   []string                      `json:"repositories,omitempty"`
	RepoVisibility string                        `json:"repo_visibility,omitempty"`
	Permissions    *gogh.InstallationPermissions `json:"permissions,omitempty"`
}

type CreateGlobalAccessTokenRes struct {
	Token     string `json:"token"`
	ExpiresAt string `json:"expires_at"`
}

func createRepositoryInstallationToken(ctx context.Context, githubAppClient *gogh.Client, ownerID ts.OwnerEID, repoID ts.RepositoryEID) (*string, error) {
	opts := &CreateGlobalAccessTokenOptions{
		TargetID:      int64(ownerID),
		RepositoryIDs: []int64{int64(repoID)},
	}

	reqJson, err := json.Marshal(opts)
	if err != nil {
		return nil, errors.Wrap(err, "failed to marshal global access token options")
	}

	url := githubAppClient.BaseURL.String() + GlobalAppAccessRoute

	req, err := http.NewRequestWithContext(ctx, "POST", url, bytes.NewReader(reqJson))
	if err != nil {
		return nil, errors.Wrap(err, "failed to create request")
	}
	req.Header.Set("Content-Type", "application/json")

	res := &CreateGlobalAccessTokenRes{}
	_, err = githubAppClient.Do(ctx, req, &res)
	if err != nil {
		return nil, errors.Wrap(err, "failed to get global app token")
	}

	return &res.Token, nil
}
