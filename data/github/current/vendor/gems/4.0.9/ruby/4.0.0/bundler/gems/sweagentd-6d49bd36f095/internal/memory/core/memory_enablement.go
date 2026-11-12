package core

import (
	"context"

	"github.com/github/sweagentd/internal/goerrors"
)

// MemoryEnablementChecker is an interface for checking if memory is enabled for a user.
type MemoryEnablementChecker interface {
	// IsMemoryEnabled checks if memory is enabled for the given user ID.
	IsMemoryEnabled(ctx context.Context, userID int64) (bool, error)
}

// checkMemoryEnabled checks if the memory feature is enabled for the given user ID
// (check is performed via the MemoryEnablementChecker which in production uses the GitHub Twirp client)
func (s *memoryService) checkMemoryEnabled(ctx context.Context, userID int64) error {
	// If we cannot perform enablement check, we consider the feature disabled (safer default)
	if s.enablementChecker == nil {
		return ErrFeatureNotEnabled
	}

	enabled, err := s.enablementChecker.IsMemoryEnabled(ctx, userID)
	if err != nil {
		return goerrors.Errorf("failed to check memory enablement: %w", err)
	}
	if !enabled {
		return ErrFeatureNotEnabled
	}
	return nil
}
