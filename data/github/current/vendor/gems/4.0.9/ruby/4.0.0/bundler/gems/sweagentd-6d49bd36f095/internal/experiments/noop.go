package experiments

import (
	"context"

	"github.com/github/sweagentd/internal/githubtwirp"
)

var _ Client = &NoopClient{}

// NoopClient is a no-operation implementation of the Client interface.
type NoopClient struct {
}

// NewNoopClient creates a new NoopClient instance.
func NewNoopClient() *NoopClient {
	return &NoopClient{}
}

// NewTrafficFiltersDefaults returns empty traffic filters.
func (e *NoopClient) NewTrafficFiltersDefaults(ctx context.Context, twirpClient githubtwirp.ClientInterface, defaultFilters *FilterProps) (TrafficFilters, error) {
	return TrafficFilters{}, nil
}

// GetFeatureAssignment returns a default assignment.
func (e *NoopClient) GetFeatureAssignment(ctx context.Context, featureName string, randomizationUnit *TrafficFilter, trafficFilters TrafficFilters) (*Assignment, bool) {
	return &Assignment{}, true
}
