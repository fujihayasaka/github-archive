package dotcom

import (
	"context"
	"errors"
	"fmt"

	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/memory/core"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
)

// ErrRepositoryNotFound is returned when a repository is not found.
var ErrRepositoryNotFound = errors.New("repository not found")

// RepositoryStore implements the RepositoryStore interface.
type RepositoryStore struct {
	clientFactory github.ClientFactoryInterface
	obsv          observability.Exporters
}

// NewRepositoryStore creates a new RepositoryStore.
func NewRepositoryStore(clientFactory github.ClientFactoryInterface, obsv observability.Exporters) *RepositoryStore {
	return &RepositoryStore{
		clientFactory: clientFactory,
		obsv:          obsv,
	}
}

// FindByNWO finds a repository by its NWO (namespace, name, owner).
func (s *RepositoryStore) FindByNWO(ctx context.Context, nwo core.RepoNWO) (*core.Repository, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "RepositoryStore.FindByNWO")
	defer span.End()
	user, ok := requestctx.User(ctx)
	if !ok {
		return nil, fmt.Errorf("user not found in context: %w", core.ErrUnauthorized)
	}
	client := s.clientFactory.NewClientForUser(user.TokenInfo.Token, user.ID)
	repo, err := client.GetRepository(ctx, nwo.Owner, nwo.Repo)
	if err != nil {
		return nil, fmt.Errorf("failed to get repository %s: %w", nwo, err)
	}

	return &core.Repository{
		ID:      core.RepositoryID(*repo.ID),
		NWO:     nwo,
		Private: repo.GetPrivate(),
	}, nil
}
