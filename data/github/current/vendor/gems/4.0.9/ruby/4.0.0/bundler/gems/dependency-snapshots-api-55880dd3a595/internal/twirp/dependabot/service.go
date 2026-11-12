package dependabot

import (
	"context"
	"fmt"
	"strconv"
	"strings"

	hydroproto "github.com/github/dependency-snapshots-api/hydro/schemas/github/dependencygraph/v1"
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
	"google.golang.org/protobuf/types/known/wrapperspb"
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

// Metadata keys expected in Dependabot snapshot payloads.
const (
	metadataKeyEventID              = "event_id"
	metadataKeyScannedManifestsPath = "scanned_manifest_path"
)

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

	stored, err := s.snapshotsSvc.StoreSnapshot(ctx, snapshot)
	if err != nil {
		contextlogger.Error(ctx, "CreateDependabotSnapshot: validating or storing snapshot", kvp.String("exception.message", err.Error()))
		return nil, twirp.WrapError(
			twirp.NewError(twirp.Internal, "validating or storing snapshot"),
			errors.Wrapf(err, "in CreateDependabotSnapshot"))
	}

	s.markAsReceived(ctx, snapshot, stored.SnapshotID)

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

	switch stored.Result {
	case interfaces.AcceptedNonDefaultBranch:
		return &proto.CreateDependabotSnapshotResponse{
			SnapshotId: stored.SnapshotID,
			CreatedAt:  timestamppb.New(stored.CreatedAt),
			Result:     proto.CreateDependabotSnapshotResponse_RESULT_ACCEPTED,
			Message:    "The snapshot was accepted, but it is not for the default branch. It will not update dependency results for the repository.",
		}, nil
	case interfaces.AcceptedHistorical:
		return &proto.CreateDependabotSnapshotResponse{
			SnapshotId: stored.SnapshotID,
			CreatedAt:  timestamppb.New(stored.CreatedAt),
			Result:     proto.CreateDependabotSnapshotResponse_RESULT_ACCEPTED,
			Message:    "The snapshot was accepted, but it is superseded by a newer snapshot from the same detector and correlator. It will not update dependency results for the repository.",
		}, nil
	case interfaces.AcceptedCanonical:
		err = s.publishDependabotSnapshotEvent(ctx, snapshot, stored)
		if err != nil {
			contextlogger.Error(ctx, "CreateDependabotSnapshot: publishing Hydro event", kvp.String("exception.message", err.Error()))
			return nil, twirp.WrapError(
				twirp.NewError(twirp.Internal, "publishing Hydro event"),
				errors.Wrapf(err, "in CreateDependabotSnapshot"))
		}

		s.statter.Counter(metricsPrefixCreateDependabotSnapshot+".published", stats.Tags{}, 1)

		return &proto.CreateDependabotSnapshotResponse{
			SnapshotId: stored.SnapshotID,
			CreatedAt:  timestamppb.New(stored.CreatedAt),
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

// publishDependabotSnapshotEvent publishes a SnapshotProcessed Hydro event
// for a Dependabot snapshot, with SNAPSHOT_TYPE_DEPENDABOT and an optional deadline.
func (s *service) publishDependabotSnapshotEvent(ctx context.Context, snapshot *interfaces.Snapshot, stored interfaces.StoreSnapshotOutput) error {
	msg := &hydroproto.SnapshotProcessed{
		RepositoryId:     int64(snapshot.RepositoryID),
		SnapshotId:       int64(stored.SnapshotID),
		Ref:              []byte(snapshot.Ref),
		Sha:              snapshot.SHA,
		DetectorName:     snapshot.Detector.Name,
		Correlator:       snapshot.Job.Correlator,
		ScannedAt:        timestamppb.New(snapshot.Scanned),
		CreatedAt:        timestamppb.New(stored.CreatedAt),
		SnapshotType:     hydroproto.SnapshotProcessed_SNAPSHOT_TYPE_DEPENDABOT,
		DependencyChange: wrapperspb.Bool(stored.DependenciesChanged),
	}

	// Populate the deadline from the event tracking data if available.
	if deadline := s.lookupEventDeadline(ctx, snapshot); deadline != nil {
		msg.Deadline = deadline
	}

	return s.publisher.Publish(ctx, msg)
}

// markAsReceived updates any matching row in our requested snapshot list for this event.
// This is best-effort: errors are logged but do not affect the snapshot response.
func (s *service) markAsReceived(ctx context.Context, snapshot *interfaces.Snapshot, snapshotID uint64) {
	eventIDStr, ok := snapshot.Metadata[metadataKeyEventID].(string)
	if !ok || eventIDStr == "" {
		// If no event_id is set, then we can assume snapshot tracking is not in
		// use and skip this for now.
		//
		// See:
		// - internal/aqueduct/dependabot_snapshot_post_push.go(RepositoryAlertingFeatureFlag)
		// - FF: `dependency_graph_parse_once_repository_alerting`
		// - https://github.com/github/dependency-graph/issues/9518
		contextlogger.Debug(ctx, "markAsReceived: event_id not present",
			kvp.Int64("snapshot_id", int64(snapshotID)),
		)
		s.statter.Counter(
			metricsPrefixCreateDependabotSnapshot+".mark_as_received.skipped",
			stats.Tags{"reason": "no_event_id"}, 1,
		)
		return
	}

	eventID, err := strconv.ParseUint(eventIDStr, 10, 64)
	if err != nil || eventID == 0 {
		contextlogger.Error(ctx, "markAsReceived: event_id is not a valid uint64",
			kvp.String("event_id", eventIDStr),
			kvp.Int64("snapshot_id", int64(snapshotID)),
		)
		s.statter.Counter(
			metricsPrefixCreateDependabotSnapshot+".mark_as_received.failure",
			stats.Tags{"reason": "event_id_invalid"}, 1,
		)
		return
	}

	ctx = contextlogger.ContextWithFields(ctx, kvp.Uint64("event_id", eventID), kvp.Uint64("snapshot_id", snapshotID))

	scannedManifestsPath, ok := snapshot.Metadata[metadataKeyScannedManifestsPath].(string)
	if !ok || scannedManifestsPath == "" {
		contextlogger.Error(ctx, "markAsReceived: scanned_manifest_path not present")
		s.statter.Counter(
			metricsPrefixCreateDependabotSnapshot+".mark_as_received.skipped",
			stats.Tags{"reason": "no_scanned_manifest_path"}, 1,
		)
		return
	}

	parts := strings.SplitN(scannedManifestsPath, "::", 2)
	if len(parts) != 2 {
		contextlogger.Error(ctx, "markAsReceived: scanned_manifest_path has invalid format",
			kvp.String("scanned_manifest_path", scannedManifestsPath),
		)
		s.statter.Counter(
			metricsPrefixCreateDependabotSnapshot+".mark_as_received.failure",
			stats.Tags{"reason": "invalid_scanned_manifest_path"}, 1,
		)
		return
	}

	ecosystemStr, manifestPath := parts[0], parts[1]

	if manifestPath == "" {
		contextlogger.Error(ctx, "markAsReceived: manifest path is blank in scanned_manifest_path",
			kvp.String("ecosystem", ecosystemStr),
		)
		s.statter.Counter(
			metricsPrefixCreateDependabotSnapshot+".mark_as_received.failure",
			stats.Tags{"reason": "blank_manifest_path"}, 1,
		)
		return
	}

	// Normalize the manifest path to match the format used at storage time
	// (filepath.Dir-style: no leading/trailing slashes, root is ".").
	manifestPath = strings.Trim(manifestPath, "/")
	if manifestPath == "" {
		manifestPath = "."
	}

	ecosystem, err := ecosystems.FromString(ecosystemStr)
	if err != nil {
		contextlogger.Error(ctx, "markAsReceived: unknown ecosystem in scanned_manifest_path",
			kvp.String("ecosystem", ecosystemStr),
		)
		s.statter.Counter(
			metricsPrefixCreateDependabotSnapshot+".mark_as_received.failure",
			stats.Tags{"reason": "unknown_ecosystem"}, 1,
		)
		return
	}

	matched, err := s.dependabotEventSvc.MarkSnapshotReceived(ctx, eventID, snapshotID, ecosystem, manifestPath)
	if err != nil {
		contextlogger.Error(ctx, "markAsReceived: failed to update requested snapshot",
			kvp.String("ecosystem", ecosystem.String()),
			kvp.String("manifest_path", manifestPath),
			kvp.String("exception.message", err.Error()),
		)
		s.statter.Counter(
			metricsPrefixCreateDependabotSnapshot+".mark_as_received.failure",
			stats.Tags{"reason": "storage_error"}, 1,
		)
		return
	}

	if matched {
		contextlogger.Info(ctx, "markAsReceived: requested snapshot marked as received",
			kvp.String("ecosystem", ecosystem.String()),
			kvp.String("manifest_path", manifestPath),
		)
		s.statter.Counter(
			metricsPrefixCreateDependabotSnapshot+".mark_as_received.success",
			stats.Tags{}, 1,
		)
	} else {
		contextlogger.Warn(ctx, "markAsReceived: no matching requested snapshot found",
			kvp.String("ecosystem", ecosystem.String()),
			kvp.String("manifest_path", manifestPath),
		)
		s.statter.Counter(
			metricsPrefixCreateDependabotSnapshot+".mark_as_received.failure",
			stats.Tags{"reason": "no_matching_entry"}, 1,
		)
	}
}

// lookupEventDeadline attempts to retrieve the deadline for the dependabot event associated
// with this snapshot. Returns nil if the event_id is not present in metadata or if the
// deadline cannot be retrieved.
func (s *service) lookupEventDeadline(ctx context.Context, snapshot *interfaces.Snapshot) *timestamppb.Timestamp {
	eventIDStr, ok := snapshot.Metadata[metadataKeyEventID].(string)
	if !ok || eventIDStr == "" {
		return nil
	}

	eventID, err := strconv.ParseUint(eventIDStr, 10, 64)
	if err != nil || eventID == 0 {
		return nil
	}

	deadline, found, err := s.dependabotEventSvc.GetEventDeadline(ctx, eventID)
	if err != nil {
		contextlogger.Warn(ctx, "lookupEventDeadline: failed to get deadline",
			kvp.Uint64("event_id", eventID),
			kvp.String("exception.message", err.Error()),
		)
		return nil
	}
	if !found {
		return nil
	}

	return timestamppb.New(deadline)
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

	result, event, err := s.dependabotEventSvc.CheckRepositoryReadiness(ctx, req.GetRepositoryId(), eventType)
	if err != nil {
		contextlogger.Error(ctx, "CheckRepositoryReadiness: checking readiness", kvp.String("exception.message", err.Error()))
		return nil, twirp.WrapError(
			twirp.NewError(twirp.Internal, "checking repository readiness"),
			errors.Wrapf(err, "in CheckRepositoryReadiness"))
	}

	return &proto.CheckRepositoryReadinessResponse{
		Ready:           result.Ready,
		Reason:          readinessReasonToProto(result.Reason),
		MostRecentEvent: dependabotEventToProto(event),
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

func internalEventTypeToProto(eventType interfaces.EventType) entities.DependabotEventType {
	switch eventType {
	case interfaces.EventTypeInit:
		return entities.DependabotEventType_DEPENDABOT_EVENT_TYPE_INIT
	case interfaces.EventTypePush:
		return entities.DependabotEventType_DEPENDABOT_EVENT_TYPE_PUSH
	default:
		return entities.DependabotEventType_DEPENDABOT_EVENT_TYPE_UNSPECIFIED
	}
}

func dependabotEventToProto(event *interfaces.DependabotEvent) *entities.DependabotEvent {
	if event == nil {
		return nil
	}
	return &entities.DependabotEvent{
		EventType: internalEventTypeToProto(event.EventType),
		Ref:       event.Ref,
		Sha:       event.SHA,
		CreatedAt: timestamppb.New(event.CreatedAt),
	}
}
