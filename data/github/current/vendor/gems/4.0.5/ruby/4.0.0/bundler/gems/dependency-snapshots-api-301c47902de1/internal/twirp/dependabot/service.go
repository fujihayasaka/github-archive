package dependabot

import (
	"context"
	"fmt"
	"path/filepath"
	"strconv"

	hydroproto "github.com/github/dependency-snapshots-api/hydro/schemas/dependency_graph/v0"
	"github.com/github/dependency-snapshots-api/internal/contextlogger"
	"github.com/github/dependency-snapshots-api/internal/ecosystems"
	"github.com/github/dependency-snapshots-api/internal/features"
	"github.com/github/dependency-snapshots-api/internal/hydro"
	"github.com/github/dependency-snapshots-api/internal/interfaces"
	"github.com/github/dependency-snapshots-api/internal/twirp/snapshots"
	"github.com/github/dependency-snapshots-api/pkg/proto"
	"github.com/github/dependency-snapshots-api/pkg/proto/entities"

	"github.com/github/github-telemetry-go/kvp"
	stats "github.com/github/go-stats"

	"buf.build/go/protovalidate"
	"github.com/pkg/errors"
	"github.com/twitchtv/twirp"
	"google.golang.org/protobuf/types/known/timestamppb"
)

// service holds the methods for our Twirp Server as well as a few dependencies.
type service struct {
	snapshotsSvc       interfaces.SnapshotsService
	dependabotEventSvc interfaces.DependabotEventService
	statter            stats.Client
	publisher          hydro.Publisher
	features           features.Client
}

// CreateTwirpServer creates a new TwirpServer instance that adheres to SnapshotsService's API.
func CreateTwirpServer(hooks *twirp.ServerHooks, statter stats.Client, features features.Client, snapshotSvc interfaces.SnapshotsService, dependabotEventSvc interfaces.DependabotEventService, publisher hydro.Publisher) proto.TwirpServer {
	server := CreateService(statter, features, snapshotSvc, dependabotEventSvc, publisher)
	return proto.NewDependabotServiceServer(server, hooks)
}

// CreateService creates a new proto.SnapshotsService.
func CreateService(statter stats.Client, features features.Client, snapshotsSvc interfaces.SnapshotsService, dependabotEventSvc interfaces.DependabotEventService, publisher hydro.Publisher) proto.DependabotService {
	service := &service{
		snapshotsSvc:       snapshotsSvc,
		dependabotEventSvc: dependabotEventSvc,
		statter:            statter,
		publisher:          publisher,
		features:           features,
	}

	return service
}

// metricsPrefixCreateDependabotSnapshot is used for all metrics emitted by the dependabot snapshot service.
const metricsPrefixCreateDependabotSnapshot = "create_dependabot_snapshot"

func (s *service) CreateDependabotSnapshot(ctx context.Context, req *proto.CreateDependabotSnapshotRequest) (*proto.CreateDependabotSnapshotResponse, error) {
	ctx, ender, _ := contextlogger.LogStartAndStop(ctx, "CreateDependabotSnapshot", "CreateDependabotSnapshot")
	defer ender()

	err := validateCreateDependabotSnapshotRequest(req)
	if err != nil {
		return &proto.CreateDependabotSnapshotResponse{
			SnapshotId: 0,
			CreatedAt:  nil,
			Result:     proto.CreateDependabotSnapshotResponse_RESULT_INVALID,
			Message:    fmt.Sprintf("Invalid request: %v", err),
		}, twirp.NewError(twirp.Malformed, fmt.Sprintf("invalid request: %v", err))
	}

	// Also, sets snapshot.Type to SnapshotTypeIncremental.
	snapshot := protoToSnapshot(req)

	if err := snapshots.ValidatePurls(ctx, snapshot); err != nil {
		return &proto.CreateDependabotSnapshotResponse{
			SnapshotId: 0,
			CreatedAt:  nil,
			Result:     proto.CreateDependabotSnapshotResponse_RESULT_INVALID,
			Message:    "Invalid package url.",
		}, twirp.NewError(twirp.Malformed, fmt.Sprintf("invalid package url: %v", err))
	}

	snapID, createdAt, result, err := s.snapshotsSvc.StoreSnapshot(ctx, snapshot)
	if err != nil {
		contextlogger.Error(ctx, "CreateDependabotSnapshot: validating or storing snapshot", kvp.String("exception.message", err.Error()))
		return nil, twirp.WrapError(
			twirp.NewError(twirp.Internal, "validating or storing snapshot"),
			errors.Wrapf(err, "in CreateDependabotSnapshot"))
	}

	s.markAsReceived(ctx, snapshot, snapID)

	s.statter.Counter(metricsPrefixCreateDependabotSnapshot+".snapshot", stats.Tags{
		"submission_type": snapshot.SubmissionType().String(),
	}, 1)
	for _, manifest := range snapshot.Manifests {
		manifestType := interfaces.InferManifestType(manifest)
		s.statter.Counter(metricsPrefixCreateDependabotSnapshot+".manifest", stats.Tags{
			"manifest_type":   manifestType,
			"submission_type": snapshot.SubmissionType().String(),
		}, 1)
	}

	switch result {
	case interfaces.AcceptedNonDefaultBranch:
		return &proto.CreateDependabotSnapshotResponse{
			SnapshotId: snapID,
			CreatedAt:  timestamppb.New(createdAt),
			Result:     proto.CreateDependabotSnapshotResponse_RESULT_ACCEPTED,
			Message:    "The snapshot was accepted, but it is not for the default branch. It will not update dependency results for the repository.",
		}, nil
	case interfaces.AcceptedHistorical:
		return &proto.CreateDependabotSnapshotResponse{
			SnapshotId: snapID,
			CreatedAt:  timestamppb.New(createdAt),
			Result:     proto.CreateDependabotSnapshotResponse_RESULT_ACCEPTED,
			Message:    "The snapshot was accepted, but it is superseded by a newer snapshot from the same detector and correlator. It will not update dependency results for the repository.",
		}, nil
	case interfaces.AcceptedCanonical:
		// TODO: Limit emitting this event to snapshots that arrive post-deadline
		//
		// See: https://github.com/github/dependency-graph/issues/9672
		err = s.publisher.Publish(ctx, &hydroproto.DependabotSnapshotReceived{
			RepositoryId: int64(snapshot.RepositoryID),
			SnapshotId:   int64(snapID),
			Ref:          []byte(snapshot.Ref),
			Sha:          snapshot.SHA,
			DetectorName: snapshot.Detector.Name,
			Correlator:   snapshot.Job.Correlator,
			ScannedAt:    timestamppb.New(snapshot.Scanned),
			CreatedAt:    timestamppb.New(createdAt),
		})

		if err != nil {
			contextlogger.Error(ctx, "CreateDependabotSnapshot: publishing Hydro event", kvp.String("exception.message", err.Error()))
			return nil, twirp.WrapError(
				twirp.NewError(twirp.Internal, "publishing Hydro event"),
				errors.Wrapf(err, "in CreateDependabotSnapshot"))
		}

		s.statter.Counter(metricsPrefixCreateDependabotSnapshot+".published", stats.Tags{}, 1)

		return &proto.CreateDependabotSnapshotResponse{
			SnapshotId: snapID,
			CreatedAt:  timestamppb.New(createdAt),
			Result:     proto.CreateDependabotSnapshotResponse_RESULT_SUCCESS,
			Message:    "Dependency results for the repo have been successfully updated.",
		}, nil
	case interfaces.SnapshotRemoved:
		return &proto.CreateDependabotSnapshotResponse{
			Result:  proto.CreateDependabotSnapshotResponse_RESULT_REMOVED,
			Message: "The snapshot was valid, but not accepted. It did not apply to the default branch or was too historical to be considered applicable to the repository and was removed.",
		}, nil
	default:
		return nil, errors.New("unexpected case statement")
	}
}

// RepositoryAlertingFeatureFlag is the name of the feature flag that controls
// whether dependabot snapshot event tracking is enabled.
const RepositoryAlertingFeatureFlag = "dependency_graph_parse_once_repository_alerting"

// markAsReceived updates any matching row in our requested snapshot list for this event.
// This is best-effort: errors are logged but do not affect the snapshot response.
func (s *service) markAsReceived(ctx context.Context, snapshot *interfaces.Snapshot, snapshotID uint64) {
	enabled, err := s.features.IsFeatureFlagEnabledForRepository(ctx, RepositoryAlertingFeatureFlag, snapshot.RepositoryID)
	if err != nil {
		contextlogger.Warn(ctx, "markAsReceived: checking feature flag", kvp.String("exception.message", err.Error()))
		s.statter.Counter(
			metricsPrefixCreateDependabotSnapshot+".mark_as_received.failure",
			stats.Tags{"reason": "feature_flag_error"}, 1,
		)
		return
	}
	if !enabled {
		return
	}

	eventIDStr, ok := snapshot.Metadata["event_id"].(string)
	if !ok || eventIDStr == "" {
		contextlogger.Warn(ctx, "markAsReceived: event_id not present",
			kvp.Int64("snapshot_id", int64(snapshotID)),
		)
		s.statter.Counter(
			metricsPrefixCreateDependabotSnapshot+".mark_as_received.failure",
			stats.Tags{"reason": "event_id_missing"}, 1,
		)
		return
	}

	eventID, err := strconv.ParseUint(eventIDStr, 10, 64)
	if err != nil || eventID == 0 {
		contextlogger.Warn(ctx, "markAsReceived: event_id is not a valid uint64",
			kvp.String("event_id", eventIDStr),
			kvp.Int64("snapshot_id", int64(snapshotID)),
		)
		s.statter.Counter(
			metricsPrefixCreateDependabotSnapshot+".mark_as_received.failure",
			stats.Tags{"reason": "event_id_invalid"}, 1,
		)
		return
	}

	// TODO: Properly handle snapshots for manifest deletion
	//
	// A deletion snapshot will not contain any manifests, so we cannot derive
	// the path using the existing logic.
	//
	// We should modify the Dependabot snapshot generation to ensure we still
	// get the manifest path for deletions
	//
	// See:
	//   - https://github.com/github/dependency-graph/issues/9769
	if len(snapshot.Manifests) == 0 {
		status, _ := snapshot.Metadata["status"].(string)
		if status == "" {
			status = "unknown"
		}
		contextlogger.Warn(ctx, "markAsReceived: snapshot has no manifests",
			kvp.Uint64("event_id", eventID),
			kvp.Int64("snapshot_id", int64(snapshotID)),
			kvp.String("status", status),
		)
		s.statter.Counter(
			metricsPrefixCreateDependabotSnapshot+".mark_as_received.failure",
			stats.Tags{"reason": "no_manifests"}, 1,
		)
		return
	}

	for _, manifest := range snapshot.Manifests {
		ecosystem, err := ecosystemFromManifest(manifest)
		if err != nil {
			contextlogger.Warn(ctx, "markAsReceived: "+err.Error(),
				kvp.Uint64("event_id", eventID),
			)
			s.statter.Counter(
				metricsPrefixCreateDependabotSnapshot+".mark_as_received.failure",
				stats.Tags{"reason": "unknown_ecosystem"}, 1,
			)
			continue
		}

		// Validate the manifest source location is non-empty
		if manifest.File.SourceLocation == "" {
			contextlogger.Warn(ctx, "markAsReceived: manifest path is blank",
				kvp.Uint64("event_id", eventID),
				kvp.String("ecosystem", ecosystem.String()),
			)
			s.statter.Counter(
				metricsPrefixCreateDependabotSnapshot+".mark_as_received.failure",
				stats.Tags{"reason": "blank_manifest_path"}, 1,
			)
			continue
		}

		// Extract the manifest path from the source location
		manifestPath := filepath.Dir(manifest.File.SourceLocation)

		matched, err := s.dependabotEventSvc.MarkSnapshotReceived(ctx, eventID, snapshotID, ecosystem, manifestPath)
		if err != nil {
			contextlogger.Warn(ctx, "markAsReceived: failed to update requested snapshot",
				kvp.Uint64("event_id", eventID),
				kvp.String("ecosystem", ecosystem.String()),
				kvp.String("manifest_path", manifestPath),
				kvp.String("exception.message", err.Error()),
			)
			s.statter.Counter(
				metricsPrefixCreateDependabotSnapshot+".mark_as_received.failure",
				stats.Tags{"reason": "storage_error"}, 1,
			)
			continue
		}

		if matched {
			contextlogger.Info(ctx, "markAsReceived: requested snapshot marked as received",
				kvp.Uint64("event_id", eventID),
				kvp.String("ecosystem", ecosystem.String()),
				kvp.String("manifest_path", manifestPath),
				kvp.Int64("snapshot_id", int64(snapshotID)),
			)
			s.statter.Counter(
				metricsPrefixCreateDependabotSnapshot+".mark_as_received.success",
				stats.Tags{}, 1,
			)
		} else {
			contextlogger.Warn(ctx, "markAsReceived: no matching requested snapshot found",
				kvp.Uint64("event_id", eventID),
				kvp.String("ecosystem", ecosystem.String()),
				kvp.String("manifest_path", manifestPath),
				kvp.Int64("snapshot_id", int64(snapshotID)),
			)
			s.statter.Counter(
				metricsPrefixCreateDependabotSnapshot+".mark_as_received.failure",
				stats.Tags{"reason": "no_matching_entry"}, 1,
			)
		}
	}
}

// ecosystemFromManifest extracts and parses the ecosystem type from manifest metadata.
func ecosystemFromManifest(manifest *interfaces.Manifest) (ecosystems.Ecosystem, error) {
	ecosystemStr, ok := manifest.Metadata["ecosystem"].(string)
	if !ok {
		return ecosystems.Unknown, fmt.Errorf("ecosystem is blank")
	}

	ecosystem, err := ecosystems.FromString(ecosystemStr)
	if err != nil {
		return ecosystems.Unknown, err
	}

	return ecosystem, nil
}

// protoToSnapshot converts a CreateDependabotSnapshotRequest protobuf message to an internal Snapshot struct.
// It assumes that the request has already been validated. It also sets Type to SnapshotTypeIncremental and
// Internal to false, as Dependabot snapshots are always incremental and internal snapshots are deprecated.
func protoToSnapshot(request *proto.CreateDependabotSnapshotRequest) *interfaces.Snapshot {
	payload := request.GetPayload()

	// Convert manifests
	manifests := make(interfaces.Manifests)
	for key, value := range payload.Manifests {
		manifests[key] = protoToManifest(value)
	}

	return &interfaces.Snapshot{
		Type:         interfaces.SnapshotTypeIncremental,
		RepositoryID: request.GetRepositoryId(),
		Version:      payload.GetVersion(),
		Job: interfaces.Job{
			ID:         payload.GetJob().GetId(),
			Correlator: payload.GetJob().GetCorrelator(),
			HTMLUrl:    payload.GetJob().GetHtmlUrl(),
		},
		SHA: payload.GetSha(),
		Ref: payload.GetRef(),
		Detector: &interfaces.DetectorMetadata{
			Name:    payload.GetDetector().GetName(),
			URL:     payload.GetDetector().GetUrl(),
			Version: payload.GetDetector().GetVersion(),
		},
		Metadata:  protoToMetadata(payload.GetMetadata()),
		Manifests: manifests,
		Scanned:   payload.GetScanned().AsTime(),
		Internal:  false, // Internal snapshots are deprecated
	}
}

func protoToManifest(manifest *entities.Manifest) *interfaces.Manifest {
	// Convert dependencies
	resolved := make(interfaces.DependencyGraph)
	for key, value := range manifest.GetResolved() {
		resolved[key] = protoToDependency(value)
	}

	return &interfaces.Manifest{
		Name: manifest.GetName(),
		File: interfaces.FileInfo{
			SourceLocation: manifest.GetFile().GetSourceLocation(),
		},
		Metadata: protoToMetadata(manifest.GetMetadata()),
		Resolved: resolved,
	}
}

func protoToDependency(dependency *entities.Dependency) *interfaces.DependencyNode {
	return &interfaces.DependencyNode{
		PackageURL:   dependency.GetPackageUrl(),
		Dependencies: dependency.GetDependencies(),
		Relationship: protoToDependencyRelationship(dependency.GetRelationship()),
		Scope:        protoToScope(dependency.GetScope()),
		Metadata:     protoToMetadata(dependency.GetMetadata()),
	}
}

func protoToMetadata(proto map[string]string) interfaces.Metadata {
	metadata := make(interfaces.Metadata)
	for k, v := range proto {
		metadata[k] = v
	}
	return metadata
}

func protoToDependencyRelationship(rel entities.Dependency_Relationship) interfaces.DependencyRelationship {
	switch rel {
	case entities.Dependency_RELATIONSHIP_DIRECT:
		return interfaces.Direct
	case entities.Dependency_RELATIONSHIP_INDIRECT:
		return interfaces.Indirect
	default:
		return interfaces.NoRelationship
	}
}

func protoToScope(scope entities.Dependency_Scope) interfaces.DependencyScope {
	switch scope {
	case entities.Dependency_SCOPE_RUNTIME:
		return interfaces.Runtime
	case entities.Dependency_SCOPE_DEVELOPMENT:
		return interfaces.Development
	default:
		return interfaces.NoScope
	}
}

func validateCreateDependabotSnapshotRequest(req *proto.CreateDependabotSnapshotRequest) error {
	return protovalidate.Validate(req)
}

func (s *service) CheckRepositoryEventReadiness(ctx context.Context, req *proto.CheckRepositoryEventReadinessRequest) (*proto.CheckRepositoryEventReadinessResponse, error) {
	ctx, ender, _ := contextlogger.LogStartAndStop(ctx, "CheckRepositoryEventReadiness", "CheckRepositoryEventReadiness")
	defer ender()

	if err := protovalidate.Validate(req); err != nil {
		return nil, twirp.NewError(twirp.Malformed, fmt.Sprintf("invalid request: %v", err))
	}

	eventType, err := protoEventTypeToInternal(req.GetEventType())
	if err != nil {
		return nil, twirp.NewError(twirp.Malformed, err.Error())
	}

	result, err := s.dependabotEventSvc.CheckDependabotEventReadiness(ctx, req.GetRepositoryId(), eventType, req.GetRef(), req.GetSha(), interfaces.WithPushID(req.GetPushId()))
	if err != nil {
		contextlogger.Error(ctx, "CheckRepositoryEventReadiness: checking readiness", kvp.String("exception.message", err.Error()))
		return nil, twirp.WrapError(
			twirp.NewError(twirp.Internal, "checking event readiness"),
			errors.Wrapf(err, "in CheckRepositoryEventReadiness"))
	}

	return &proto.CheckRepositoryEventReadinessResponse{
		Ready:  result.Ready,
		Reason: readinessReasonToProto(result.Reason),
	}, nil
}

func (s *service) CheckRepositoryReadiness(ctx context.Context, req *proto.CheckRepositoryReadinessRequest) (*proto.CheckRepositoryReadinessResponse, error) {
	ctx, ender, _ := contextlogger.LogStartAndStop(ctx, "CheckRepositoryReadiness", "CheckRepositoryReadiness")
	defer ender()

	if err := protovalidate.Validate(req); err != nil {
		return nil, twirp.NewError(twirp.Malformed, fmt.Sprintf("invalid request: %v", err))
	}

	var eventType *interfaces.EventType
	if req.GetEventType() != entities.DependabotEventType_DEPENDABOT_EVENT_TYPE_UNSPECIFIED {
		et, err := protoEventTypeToInternal(req.GetEventType())
		if err != nil {
			return nil, twirp.NewError(twirp.Malformed, err.Error())
		}
		eventType = &et
	}

	result, err := s.dependabotEventSvc.CheckRepositoryReadiness(ctx, req.GetRepositoryId(), eventType)
	if err != nil {
		contextlogger.Error(ctx, "CheckRepositoryReadiness: checking readiness", kvp.String("exception.message", err.Error()))
		return nil, twirp.WrapError(
			twirp.NewError(twirp.Internal, "checking repository readiness"),
			errors.Wrapf(err, "in CheckRepositoryReadiness"))
	}

	return &proto.CheckRepositoryReadinessResponse{
		Ready:  result.Ready,
		Reason: readinessReasonToProto(result.Reason),
	}, nil
}

func (s *service) CheckEventReadiness(ctx context.Context, req *proto.CheckEventReadinessRequest) (*proto.CheckEventReadinessResponse, error) {
	ctx, ender, _ := contextlogger.LogStartAndStop(ctx, "CheckEventReadiness", "CheckEventReadiness")
	defer ender()

	validator, err := protovalidate.New()
	if err != nil {
		contextlogger.Error(ctx, "CheckEventReadiness: creating validator", kvp.String("exception.message", err.Error()))
		return nil, twirp.WrapError(
			twirp.NewError(twirp.Internal, "validating request"),
			errors.Wrapf(err, "in CheckEventReadiness creating validator"),
		)
	}

	if err := validator.Validate(req); err != nil {
		return nil, twirp.WrapError(
			twirp.NewError(twirp.InvalidArgument, "invalid request"),
			errors.Wrapf(err, "in CheckEventReadiness validating request"),
		)
	}

	result, err := s.dependabotEventSvc.CheckEventReadiness(ctx, req.GetDependabotEventId())
	if err != nil {
		contextlogger.Error(ctx, "CheckEventReadiness: checking readiness", kvp.String("exception.message", err.Error()))
		return nil, twirp.WrapError(
			twirp.NewError(twirp.Internal, "checking event readiness"),
			errors.Wrapf(err, "in CheckEventReadiness"))
	}

	return &proto.CheckEventReadinessResponse{
		Ready:  result.Ready,
		Reason: readinessReasonToProto(result.Reason),
	}, nil
}

func protoEventTypeToInternal(eventType entities.DependabotEventType) (interfaces.EventType, error) {
	switch eventType {
	case entities.DependabotEventType_DEPENDABOT_EVENT_TYPE_INIT:
		return interfaces.EventTypeInit, nil
	case entities.DependabotEventType_DEPENDABOT_EVENT_TYPE_PUSH:
		return interfaces.EventTypePush, nil
	default:
		return "", fmt.Errorf("unsupported event type: %v", eventType)
	}
}

func readinessReasonToProto(reason interfaces.ReadinessReason) entities.DependabotReadinessReason {
	switch reason {
	case interfaces.ReadinessReasonNoEvent:
		return entities.DependabotReadinessReason_DEPENDABOT_READINESS_REASON_NO_EVENT
	case interfaces.ReadinessReasonPending:
		return entities.DependabotReadinessReason_DEPENDABOT_READINESS_REASON_PENDING
	case interfaces.ReadinessReasonSnapshotComplete:
		return entities.DependabotReadinessReason_DEPENDABOT_READINESS_REASON_SNAPSHOT_COMPLETE
	case interfaces.ReadinessReasonDeadlinePastPartialSnapshot:
		return entities.DependabotReadinessReason_DEPENDABOT_READINESS_REASON_DEADLINE_PAST_PARTIAL_SNAPSHOT
	case interfaces.ReadinessReasonDeadlinePastNoSnapshot:
		return entities.DependabotReadinessReason_DEPENDABOT_READINESS_REASON_DEADLINE_PAST_NO_SNAPSHOT
	default:
		return entities.DependabotReadinessReason_DEPENDABOT_READINESS_REASON_UNSPECIFIED
	}
}
