package customagent

import (
	"context"
	"errors"
	"fmt"

	repositoriesTwirp "github.com/github/github-proto/gen/go/repositories/v1"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/twitchtv/twirp"
)

type twirpRepoProvider struct {
	ghtwirp githubtwirp.ClientInterface
}

func newTwirpRepoProvider(ghtwirp githubtwirp.ClientInterface) *twirpRepoProvider {
	return &twirpRepoProvider{ghtwirp}
}

type twirpRepo struct {
	id      int64
	ownerID int64
	owner   string
	name    string
}

func newTwirpRepo(id, ownerID int64, owner, name string) *twirpRepo {
	return &twirpRepo{id: id, ownerID: ownerID, owner: owner, name: name}
}

func (r *twirpRepo) GetID() int64 {
	return r.id
}

func (r *twirpRepo) GetName() string {
	return r.name
}

func (r *twirpRepo) GetOwnerID() int64 {
	return r.ownerID
}

func (r *twirpRepo) GetOwnerName() string {
	return r.owner
}

func (r *twirpRepoProvider) getRepository(ctx context.Context, owner, repo string) (repo, error) {
	req := &repositoriesTwirp.FindRepositoriesByNameRequest{
		Nwos: []string{fmt.Sprintf("%s/%s", owner, repo)},
	}
	resp, err := r.ghtwirp.RepositoriesAPI().FindRepositoriesByName(ctx, req)
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

	return newTwirpRepo(tr.GetId(), tr.GetOwnerId(), tr.GetOwnerLogin(), tr.GetName()), nil
}

func (r *twirpRepoProvider) getRepositoryByID(ctx context.Context, id int64) (repo, error) {
	tr, err := r.ghtwirp.GetRepoById(ctx, id)
	if err != nil {
		// GetRepoById has its own ErrRepoNotFound type so we need to convert it
		if errors.Is(err, githubtwirp.ErrRepoNotFound) {
			return nil, ErrRepoNotFound
		}
		return nil, err
	}
	return newTwirpRepo(tr.GetId(), tr.GetOwnerId(), tr.GetOwnerLogin(), tr.GetName()), nil
}
