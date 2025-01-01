// Package mockghghtwirp is a helper package for running an end to end tests
package mockghghtwirp

import (
	"context"
	"net/http"

	repositories "github.com/github/turboscan/ts/monolith_twirp/repositories/v1"
)

type mockRepositories struct{}

// GetRepository retrieves a specific repository mapped the given identifier
func (r *mockRepositories) FindRepositories(_ context.Context, _ *repositories.FindRepositoriesRequest) (*repositories.FindRepositoriesResponse, error) {
	return &repositories.FindRepositoriesResponse{}, nil
}

func NewMockRepoServer() http.Handler {
	return repositories.NewRepositoriesAPIServer(&mockRepositories{})
}
