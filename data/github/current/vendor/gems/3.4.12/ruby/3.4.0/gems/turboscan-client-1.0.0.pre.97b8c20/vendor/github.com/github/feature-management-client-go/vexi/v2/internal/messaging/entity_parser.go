package messaging

import (
	"github.com/github/feature-management-client-go/vexi/v2/featureflag"
	"github.com/github/feature-management-client-go/vexi/v2/segment"
)

const (
	// FeatureFlagEntity is the entity name for feature flag changes.
	FeatureFlagEntity string = "feature flag"

	// SegmentEntity is the entity name for segment changes.
	SegmentEntity string = "segment"
)

// EntityParser is an interface that defines methods to convert binary payloads into vexi entities.
type EntityParser interface {
	ParseFeatureFlagMessagePayload(payload []byte) (*featureflag.FeatureFlag, error)
	ParseSegmentMessagePayload(payload []byte) (*segment.Segment, error)
}
