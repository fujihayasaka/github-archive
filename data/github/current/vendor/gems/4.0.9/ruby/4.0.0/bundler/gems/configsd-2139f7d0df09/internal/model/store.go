package model

import (
	"context"
)

// Store defines the interface for configuration data storage.
type Store interface {
	AllProperties(ctx context.Context, target ConfigurationTarget) (map[string]Configuration, error)
	ResolvedConfigsByTargetWithOwners(ctx context.Context, targets []ConfigurationTarget) (map[string]Configuration, error)
	SetRepositoryOwner(ctx context.Context, repoID, ownerID uint64) error
}
