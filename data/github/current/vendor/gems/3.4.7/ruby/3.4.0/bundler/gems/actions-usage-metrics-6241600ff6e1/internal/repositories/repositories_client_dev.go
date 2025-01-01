//go:build dev

package repositories

import (
	"context"
	"fmt"
	"strconv"

	"github.com/github/actions-usage-metrics/internal/config"
	twirpRepositories "github.com/github/github-proto/gen/go/repositories/v1"
)

func SetRepositoriesClient(cfg config.HttpConfig) error {
	repositoryClient = getStubRepositoriesApi()
	return nil
}

type repositoriesAPIStub struct {
	twirpRepositories.RepositoriesAPI
}

func (r repositoriesAPIStub) FindRepositories(ctx context.Context, req *twirpRepositories.FindRepositoriesRequest) (*twirpRepositories.FindRepositoriesResponse, error) {
	repos := convertIdsToRepos(req.Ids)

	response := twirpRepositories.FindRepositoriesResponse{
		Repositories: repos,
	}

	return &response, nil
}

// FindRepositoryPermissions retrieves a user permissions for the specified repositories.
func (r repositoriesAPIStub) FindRepositoryPermissions(ctx context.Context, req *twirpRepositories.FindRepositoryPermissionsRequest) (*twirpRepositories.FindRepositoryPermissionsResponse, error) {
	return nil, fmt.Errorf("Undefined method FindRepositoryPermissions")
}

// FindRepositoryByName retrieves a list of repositories by name (name with owner).
func (r repositoriesAPIStub) FindRepositoriesByName(ctx context.Context, req *twirpRepositories.FindRepositoriesByNameRequest) (*twirpRepositories.FindRepositoriesByNameResponse, error) {
	return nil, fmt.Errorf("Undefined method FindRepositoryPermissions")
}

func convertIdsToRepos(ids []int64) []*twirpRepositories.RepositoryListItem {
	repos := make([]*twirpRepositories.RepositoryListItem, 0, len(ids))
	for _, id := range ids {
		idStr := strconv.FormatInt(id, 10)
		name := fmt.Sprintf("repo-%s", idStr)
		repos = append(repos, &twirpRepositories.RepositoryListItem{
			Name: name,
			Id:   id,
		})
	}
	return repos
}

func getStubRepositoriesApi() twirpRepositories.RepositoriesAPI {
	return &repositoriesAPIStub{}
}
