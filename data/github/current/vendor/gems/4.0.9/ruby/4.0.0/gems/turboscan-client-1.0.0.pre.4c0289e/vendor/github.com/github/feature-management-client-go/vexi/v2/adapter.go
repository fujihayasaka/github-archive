package vexi

import (
	"context"

	"github.com/github/feature-management-client-go/vexi/v2/featureflag"
	"github.com/github/feature-management-client-go/vexi/v2/segment"
)

// Adapter is the interface that all adapters must implement.
type Adapter interface {
	// GetFeatureFlags returns the specified feature flags as a slice.
	// If a feature flag does not exist, it will not be included in the returned slice.
	GetFeatureFlags(ctx context.Context, names ...string) ([]*featureflag.FeatureFlag, error)

	// GetSegments returns the specified segments as a slice.
	// If a segment does not exist, it will not be included in the returned slice.
	GetSegments(ctx context.Context, names ...string) ([]*segment.Segment, error)

	// Name returns the name of the adapter.
	Name() string
}
