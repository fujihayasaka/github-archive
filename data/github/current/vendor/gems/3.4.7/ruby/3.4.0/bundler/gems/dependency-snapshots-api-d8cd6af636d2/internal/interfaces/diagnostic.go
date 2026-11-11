package interfaces

import "context"

type DiagnosticService interface {
	Ping() string
	Boom(shouldPanic bool) (bool, error)
	Timeout(sleepDurationSecs int32)
	IsFeatureFlagEnabled(ctx context.Context, feature string, actors ...string) ([]bool, error)
	IsFeatureFlagEnabledForRepository(ctx context.Context, feature string, repositoryID uint64) (bool, error)
}
