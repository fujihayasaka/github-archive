package diagnostic

import (
	"context"
	"time"

	"github.com/github/dependency-snapshots-api/internal/features"

	"github.com/pkg/errors"
)

type DiagnosticService struct {
	featuresClient features.Client
}

func NewDiagnosticService(fc features.Client) *DiagnosticService {
	return &DiagnosticService{featuresClient: fc}
}

func (s *DiagnosticService) Ping() string {
	return "pong"
}

func (s *DiagnosticService) Boom(shouldPanic bool) (bool, error) {
	if shouldPanic {
		panic("everything is broken")
	} else {
		return false, errors.New("everything is broken")
	}
}

func (s *DiagnosticService) Timeout(sleepDurationSecs int32) {
	if sleepDurationSecs == 0 {
		sleepDurationSecs = 5 * 60
	}

	time.Sleep(time.Second * time.Duration(sleepDurationSecs))
}

func (s *DiagnosticService) IsFeatureFlagEnabled(ctx context.Context, feature string, actors ...string) ([]bool, error) {
	return s.featuresClient.IsFeatureFlagEnabled(ctx, feature, actors...)
}

func (s *DiagnosticService) IsFeatureFlagEnabledForRepository(ctx context.Context, feature string, repositoryID uint64) (bool, error) {
	return s.featuresClient.IsFeatureFlagEnabledForRepository(ctx, feature, repositoryID)
}
