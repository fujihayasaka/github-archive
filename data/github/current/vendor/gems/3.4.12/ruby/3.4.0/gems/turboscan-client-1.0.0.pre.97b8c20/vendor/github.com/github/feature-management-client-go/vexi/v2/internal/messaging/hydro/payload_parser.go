// Package hydro contains hydro specific implementation of the change subscriber.
package hydro

import (
	"slices"

	vexi_errors "github.com/github/feature-management-client-go/vexi/v2/errors"
	"github.com/github/feature-management-client-go/vexi/v2/featureflag"
	"github.com/github/feature-management-client-go/vexi/v2/internal"
	hydro_pb "github.com/github/feature-management-client-go/vexi/v2/proto/hydro/schemas/featureflags/data/v0"
	entities_pb "github.com/github/feature-management-client-go/vexi/v2/proto/hydro/schemas/featureflags/data/v0/entities"
	"github.com/github/feature-management-client-go/vexi/v2/segment"
	"google.golang.org/protobuf/proto"
)

// PayloadParser defines the methods needed by the subscriber to parse the message payload as hydro protobuf models and convert it to the models used by the hydro adapter service.
type PayloadParser struct {
	t internal.Telemetry
}

// NewPayloadParser creates a new MessagePayloadParser instance.
func NewPayloadParser(t internal.Telemetry) *PayloadParser {
	return &PayloadParser{
		t: t,
	}
}

// ParseFeatureFlagMessagePayload parses the provided message payload as a hydro FeatureFlag message.
func (p *PayloadParser) ParseFeatureFlagMessagePayload(payload []byte) (*featureflag.FeatureFlag, error) {
	// Parse the payload as a hydro FeatureFlag message.
	var hydroFeatureFlag hydro_pb.FeatureFlag
	err := proto.Unmarshal(payload, &hydroFeatureFlag)
	if err != nil {
		return nil, vexi_errors.NewWrappedError(err, "error parsing feature flag message payload as hydro protobug feature flag model")
	}

	// Convert the hydro FeatureFlag message to the checks FeatureFlag model.
	checksFlag := hydroFeatureFlagToInternalFeatureFlag(&hydroFeatureFlag)
	if checksFlag.Name == "" {
		return nil, vexi_errors.NewValidationError("feature flag name is missing in the parsed hydro feature flag")
	}

	return checksFlag, nil
}

// ParseSegmentMessagePayload parses the provided message payload as a hydro Segment message.
func (p *PayloadParser) ParseSegmentMessagePayload(payload []byte) (*segment.Segment, error) {
	// Parse the payload as a hydro Segment message.
	var hydroSegment hydro_pb.Segment
	err := proto.Unmarshal(payload, &hydroSegment)
	if err != nil {
		return nil, vexi_errors.NewWrappedError(err, "error parsing segment message payload as hydro protobug segment model")
	}

	// Convert the hydro Segment message to the checks Segment model.
	checksSegment := hydroSegmentToInternalSegment(&hydroSegment)
	if checksSegment.Name == "" {
		return nil, vexi_errors.NewValidationError("segment name is missing in the parsed hydro segment")
	}

	return checksSegment, nil
}

// hydroFeatureFlagToInternalFeatureFlag converts a hydro feature flag proto definition into the vexi format.
func hydroFeatureFlagToInternalFeatureFlag(hydroFeatureFlag *hydro_pb.FeatureFlag) *featureflag.FeatureFlag {
	checksFlag := &featureflag.FeatureFlag{
		Name:               hydroFeatureFlag.Name,
		PercentageOfActors: hydroFeatureFlag.PercentageOfActors,
		PercentageOfCalls:  hydroFeatureFlag.PercentageOfCalls,
		CustomGates:        hydroFeatureFlag.CustomGates,
		Segments:           hydroFeatureFlag.Segments,
		OwningService:      hydroFeatureFlag.OwningService,
	}

	switch hydroFeatureFlag.State {
	case entities_pb.FeatureFlagState_DISABLED:
		checksFlag.BooleanGate = false
	case entities_pb.FeatureFlagState_SHIPPED:
		checksFlag.BooleanGate = true
	}

	// Deal with the fact that the default segment might be needed and not in the segment array.
	if hydroFeatureFlag.State == entities_pb.FeatureFlagState_PARTIALLY_SHIPPED &&
		hydroFeatureFlag.DefaultSegment != "" {
		if !slices.Contains(checksFlag.Segments, hydroFeatureFlag.DefaultSegment) {
			checksFlag.Segments = append(checksFlag.Segments, hydroFeatureFlag.DefaultSegment)
		}
	}

	checksFlag.OwningService = hydroFeatureFlag.OwningService
	checksFlag.UpdatedAt = hydroFeatureFlag.UpdatedAt.AsTime()

	return checksFlag
}

// hydroSegmentToInternalSegment converts a hydro segment proto definition into the vexi format.
func hydroSegmentToInternalSegment(hydroSegment *hydro_pb.Segment) *segment.Segment {
	checksSegment := &segment.Segment{
		Name:          hydroSegment.Name,
		OwningService: hydroSegment.OwningService,
	}

	// Sort the actors.
	actors := make(map[string]bool)
	for actor := range hydroSegment.Actors {
		actors[actor] = true
	}

	checksSegment.Actors = actors

	checksSegment.OwningService = hydroSegment.OwningService
	checksSegment.UpdatedAt = hydroSegment.UpdatedAt.AsTime()

	return checksSegment
}
