package githubtwirp

import (
	"context"
	"errors"

	repositoriesTwirp "github.com/github/github-proto/gen/go/repositories/v1"
	"github.com/twitchtv/twirp"
)

var ErrRepoNotFound = errors.New("repo not found")

func (gh *Client) GetRepoById(ctx context.Context, id int64) (*repositoriesTwirp.RepositoryListItem, error) {
	ctx, span := gh.obsv.Tracer.Start(ctx, "githubtwirp.Client.GetRepoById")
	defer span.End()

	req := &repositoriesTwirp.FindRepositoriesRequest{
		Ids: []int64{id},
	}
	resp, err := gh.RepositoriesAPI().FindRepositories(ctx, req)
	if err != nil {
		var twirpErr twirp.Error
		if ok := errors.As(err, &twirpErr); ok && twirpErr.Code() == twirp.NotFound {
			return nil, ErrRepoNotFound
		}
		return nil, err
	}

	repos := resp.GetRepositories()
	if len(repos) == 0 {
		return nil, ErrRepoNotFound
	}
	tr := repos[0]

	return tr, nil
}
