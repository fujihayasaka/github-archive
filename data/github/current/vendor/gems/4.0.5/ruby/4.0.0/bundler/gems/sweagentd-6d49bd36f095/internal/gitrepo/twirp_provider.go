package gitrepo

import (
	"context"
	"errors"
	"fmt"

	repositoriesTwirp "github.com/github/github-proto/gen/go/repositories/v1"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/twitchtv/twirp"
)

// ErrRepoNotFound is returned when a repository is not found.
var ErrRepoNotFound = errors.New("repository not found")

// TwirpRepoProvider implements RepoProvider using GitHub Twirp APIs.
type TwirpRepoProvider struct {
	ghtwirp githubtwirp.ClientInterface
}

// NewTwirpRepoProvider creates a new TwirpRepoProvider.
func NewTwirpRepoProvider(ghtwirp githubtwirp.ClientInterface) *TwirpRepoProvider {
	return &TwirpRepoProvider{ghtwirp: ghtwirp}
}

// twirpRepo implements the Repo interface.
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

// GetRepository fetches repository metadata by owner and name.
func (p *TwirpRepoProvider) GetRepository(ctx context.Context, owner, repoName string) (Repo, error) {
	req := &repositoriesTwirp.FindRepositoriesByNameRequest{
		Nwos: []string{fmt.Sprintf("%s/%s", owner, repoName)},
	}
	resp, err := p.ghtwirp.RepositoriesAPI().FindRepositoriesByName(ctx, req)
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

// GetRepositoryByID fetches repository metadata by ID.
func (p *TwirpRepoProvider) GetRepositoryByID(ctx context.Context, id int64) (Repo, error) {
	tr, err := p.ghtwirp.GetRepoById(ctx, id)
	if err != nil {
		if errors.Is(err, githubtwirp.ErrRepoNotFound) {
			return nil, ErrRepoNotFound
		}
		return nil, err
	}
	return newTwirpRepo(tr.GetId(), tr.GetOwnerId(), tr.GetOwnerLogin(), tr.GetName()), nil
}
