package snapshots

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"os"
	"regexp"
	"strconv"
	"strings"

	hydroproto "github.com/github/dependency-snapshots-api/hydro/schemas/github/dependencygraph/v1"
	"github.com/github/dependency-snapshots-api/internal/contextlogger"
	"github.com/github/dependency-snapshots-api/internal/features"
	"github.com/github/dependency-snapshots-api/internal/hydro"
	"github.com/github/dependency-snapshots-api/internal/interfaces"
	"github.com/github/dependency-snapshots-api/pkg/proto"
	"github.com/github/github-telemetry-go/kvp"
	stats "github.com/github/go-stats"

	"github.com/pkg/errors"
	"github.com/twitchtv/twirp"
	"google.golang.org/protobuf/types/known/timestamppb"
	"google.golang.org/protobuf/types/known/wrapperspb"
)

// NonExpiringSnapshotsFeatureFlag is the name of the feature flag that determines
// whether snapshots should be created as incremental (non-expiring) instead of complete.
const NonExpiringSnapshotsFeatureFlag = "dependency_graph_non_expiring_snapshots"

// service holds the methods for our Twirp Server as well as a few dependencies.
type service struct {
	snapshotsSvc interfaces.SnapshotsService
	statter      stats.Client
	features     features.Client
	publisher    hydro.Publisher
}

// CreateTwirpServer creates a new TwirpServer instance that adheres to SnapshotsService's API.
func CreateTwirpServer(hooks *twirp.ServerHooks, statter stats.Client, features features.Client, snapshotSvc interfaces.SnapshotsService, publisher hydro.Publisher) proto.TwirpServer {
	server := CreateService(statter, features, snapshotSvc, publisher)
	return proto.NewSnapshotsServiceServer(server, hooks)
}

// CreateService creates a new proto.SnapshotsService.
func CreateService(statter stats.Client, features features.Client, snapshotSvc interfaces.SnapshotsService, publisher hydro.Publisher) proto.SnapshotsService {
	service := &service{
		snapshotsSvc: snapshotSvc,
		statter:      statter,
		features:     features,
		publisher:    publisher,
	}

	return service
}

func (s *service) CreateDependencySnapshot(ctx context.Context, req *proto.CreateDependencySnapshotRequest) (*proto.CreateDependencySnapshotResponse, error) {
	payloadSize := len(req.Payload)
	ctx, ender, _ := contextlogger.LogStartAndStop(ctx, "CreateDependencySnapshot", "CreateDependencySnapshot",
		kvp.Int("payload.size", payloadSize),
	)
	defer ender()
	var snapshot interfaces.Snapshot
	if err := json.Unmarshal(req.GetPayload(), &snapshot); err != nil {
		contextlogger.Error(ctx, "CreateDependencySnapshot: deserializing snapshot", kvp.String("exception.message", err.Error()))
		return &proto.CreateDependencySnapshotResponse{
				SnapshotId: 0,
				CreatedAt:  nil,
				Result:     proto.CreateDependencySnapshotResponse_INVALID,
				Message:    "Error deserializing snapshot.",
			}, twirp.WrapError(
				twirp.NewError(twirp.InvalidArgument, "deserializing snapshot"),
				errors.Wrapf(err, "in CreateDependencySnapshot"))
	}

	if err := ValidatePurls(ctx, &snapshot); err != nil {
		return &proto.CreateDependencySnapshotResponse{
			SnapshotId: 0,
			CreatedAt:  nil,
			Result:     proto.CreateDependencySnapshotResponse_INVALID,
			Message:    "Invalid package url.",
		}, twirp.NewError(twirp.Malformed, fmt.Sprintf("invalid package url: %v", err))
	}

	if err := ValidateDetectorName(ctx, &snapshot); err != nil {
		return &proto.CreateDependencySnapshotResponse{
			SnapshotId: 0,
			CreatedAt:  nil,
			Result:     proto.CreateDependencySnapshotResponse_INVALID,
			Message:    err.Error(),
		}, twirp.NewError(twirp.Malformed, fmt.Sprintf("invalid detector name: %v", err))
	}

	// inject repo ID included in request and validated upstream in the monolith
	snapshot.RepositoryID = req.GetRepositoryId()

	// Set snapshot type based on feature flag
	// When the non-expiring snapshots feature flag is enabled, create incremental snapshots
	// which don't expire and are only ever directly replaced
	nonExpiringEnabled, err := s.features.IsFeatureFlagEnabledForRepository(ctx, NonExpiringSnapshotsFeatureFlag, snapshot.RepositoryID)
	if err != nil {
		contextlogger.Warn(ctx, "CreateDependencySnapshot: checking feature flag", kvp.String("exception.message", err.Error()))
		// Default to complete snapshots if we can't check the feature flag
		nonExpiringEnabled = false
	}

	if nonExpiringEnabled {
		snapshot.Type = interfaces.SnapshotTypeIncremental
	} else {
		snapshot.Type = interfaces.SnapshotTypeComplete
	}

	stored, err := s.snapshotsSvc.StoreSnapshot(ctx, &snapshot)
	if err != nil {
		contextlogger.Error(ctx, "CreateDependencySnapshot: validating or storing snapshot", kvp.String("exception.message", err.Error()))
		return nil, twirp.WrapError(
			twirp.NewError(twirp.Internal, "validating or storing snapshot"),
			errors.Wrapf(err, "in CreateDependencySnapshot"))
	}

	s.statter.Counter("create_dependency_snapshot.snapshot", stats.Tags{
		"submission_type": snapshot.SubmissionType().String(),
	}, 1)
	for _, manifest := range snapshot.Manifests {
		manifestType := interfaces.InferManifestType(manifest)
		s.statter.Counter("create_dependency_snapshot.manifest", stats.Tags{
			"manifest_type":   manifestType,
			"submission_type": snapshot.SubmissionType().String(),
		}, 1)
	}

	// Publish a SnapshotProcessed Hydro event.
	// This is best-effort: failures are logged but do not affect the response.
	s.publishSnapshotProcessed(ctx, &snapshot, stored)

	switch stored.Result {
	case interfaces.AcceptedNonDefaultBranch:
		return &proto.CreateDependencySnapshotResponse{
			SnapshotId: stored.SnapshotID,
			CreatedAt:  timestamppb.New(stored.CreatedAt),
			Result:     proto.CreateDependencySnapshotResponse_ACCEPTED,
			Message:    "The snapshot was accepted, but it is not for the default branch. It will not update dependency results for the repository.",
		}, nil
	case interfaces.AcceptedHistorical:
		return &proto.CreateDependencySnapshotResponse{
			SnapshotId: stored.SnapshotID,
			CreatedAt:  timestamppb.New(stored.CreatedAt),
			Result:     proto.CreateDependencySnapshotResponse_ACCEPTED,
			Message:    "The snapshot was accepted, but it is superseded by a newer snapshot from the same detector and correlator. It will not update dependency results for the repository.",
		}, nil
	case interfaces.AcceptedCanonical:
		return &proto.CreateDependencySnapshotResponse{
			SnapshotId: stored.SnapshotID,
			CreatedAt:  timestamppb.New(stored.CreatedAt),
			Result:     proto.CreateDependencySnapshotResponse_SUCCESS,
			Message:    "Dependency results for the repo have been successfully updated.",
		}, nil
	case interfaces.SnapshotRemoved:
		return &proto.CreateDependencySnapshotResponse{
			Result:  proto.CreateDependencySnapshotResponse_REMOVED,
			Message: "The snapshot was valid, but not accepted. It did not apply to the default branch or was too historical to be considered applicable to the repository and was removed.",
		}, nil
	}
	return nil, errors.New("unexpected case statement")
}

// publishSnapshotProcessed publishes a SnapshotProcessed Hydro event for
// external (non-Dependabot) snapshots. Publishing is best-effort: failures
// are logged but do not affect the response to the caller.
func (s *service) publishSnapshotProcessed(ctx context.Context, snapshot *interfaces.Snapshot, stored interfaces.StoreSnapshotOutput) {
	// Don't publish for removed snapshots — they have snapshotID=0 and zero createdAt.
	if stored.Result == interfaces.SnapshotRemoved {
		return
	}

	if s.publisher == nil {
		contextlogger.Warn(ctx, "publishSnapshotProcessed: publisher is nil; skipping Hydro event",
			kvp.Int64("gh.repo.id", int64(snapshot.RepositoryID)),
			kvp.Int64("snapshot_id", int64(stored.SnapshotID)),
		)
		s.statter.Counter("create_dependency_snapshot.publish.failure", stats.Tags{}, 1)
		return
	}

	detectorName := ""
	if snapshot.Detector != nil {
		detectorName = snapshot.Detector.Name
	}

	msg := &hydroproto.SnapshotProcessed{
		RepositoryId:     int64(snapshot.RepositoryID),
		SnapshotId:       int64(stored.SnapshotID),
		Ref:              []byte(snapshot.Ref),
		Sha:              snapshot.SHA,
		DetectorName:     detectorName,
		Correlator:       snapshot.Job.Correlator,
		ScannedAt:        timestamppb.New(snapshot.Scanned),
		CreatedAt:        timestamppb.New(stored.CreatedAt),
		SnapshotType:     hydroproto.SnapshotProcessed_SNAPSHOT_TYPE_EXTERNAL,
		DependencyChange: wrapperspb.Bool(stored.DependenciesChanged),
	}

	if err := s.publisher.Publish(ctx, msg); err != nil {
		contextlogger.Warn(ctx, "publishSnapshotProcessed: publishing Hydro event",
			kvp.String("exception.message", err.Error()),
			kvp.Int64("gh.repo.id", int64(snapshot.RepositoryID)),
			kvp.Int64("snapshot_id", int64(stored.SnapshotID)),
		)
		s.statter.Counter("create_dependency_snapshot.publish.failure", stats.Tags{}, 1)
		return
	}

	s.statter.Counter("create_dependency_snapshot.publish.success", stats.Tags{}, 1)
}

func (s *service) GetDependencySnapshot(ctx context.Context, req *proto.GetDependencySnapshotRequest) (*proto.GetDependencySnapshotResponse, error) {
	var snapshot *interfaces.Snapshot
	var err error
	if req.GetSnapshotId() == 0 {
		return nil, twirp.WrapError(
			twirp.NewError(twirp.NotFound, "snapshot not found"),
			errors.Wrapf(err, "in GetDependencySnapshot"))
	}

	snapshot, err = s.snapshotsSvc.SnapshotByID(ctx, req.GetRepositoryId(), req.GetSnapshotId())
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, twirp.WrapError(
				twirp.NewError(twirp.NotFound, "snapshot not found"),
				errors.Wrapf(err, "in GetDependencySnapshot"))
		}

		contextlogger.Error(ctx, "GetDependencySnapshot: retrieving snapshot", kvp.String("exception.message", err.Error()))
		return nil, twirp.WrapError(
			twirp.NewError(twirp.Internal, "retrieving snapshot"),
			errors.Wrapf(err, "in GetDependencySnapshot"))
	}

	if snapshot == nil {
		return nil, twirp.NotFoundError("snapshot not found")
	}

	payload, err := snapshot.MarshalJSON()
	if err != nil {
		return nil, twirp.WrapError(
			twirp.NewError(twirp.Internal, "serializing snapshot"),
			errors.Wrapf(err, "in GetDependencySnapshot: serializing snapshot JSON"))
	}

	return &proto.GetDependencySnapshotResponse{
		RepositoryId: snapshot.RepositoryID,
		SnapshotId:   snapshot.ID,
		Payload:      payload,
	}, nil
}

// This method is currently used for support tooling and isn't necessarily meant for full production use.
func (s *service) GetIncludedDependencySnapshots(ctx context.Context, req *proto.GetIncludedDependencySnapshotsRequest) (*proto.GetIncludedDependencySnapshotsResponse, error) {
	snapshots, err := s.snapshotsSvc.CanonicalSnapshotsForRepository(ctx, req.RepositoryId, interfaces.IncludeInternal)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, twirp.WrapError(
				twirp.NewError(twirp.NotFound, "no included snapshots found"),
				errors.Wrapf(err, "in GetIncludedDependencySnapshots"))
		}

		return nil, twirp.WrapError(
			twirp.NewError(twirp.Internal, "getting included dependency snapshots"),
			errors.Wrapf(err, "in GetIncludedDependencySnapshots"))
	}

	includedSnapshots := make([]*proto.GetIncludedDependencySnapshotsResponse_IncludedSnapshot, len(snapshots))
	for i, snap := range snapshots {
		includedSnapshots[i] = &proto.GetIncludedDependencySnapshotsResponse_IncludedSnapshot{
			SnapshotId: snap.ID,
			Correlator: snap.Job.Correlator,
			Detector:   snap.Detector.Name,
			CreatedAt:  timestamppb.New(snap.CreatedAt),
		}
	}

	return &proto.GetIncludedDependencySnapshotsResponse{IncludedSnapshots: includedSnapshots}, nil
}

// This method is currently used for support tooling and isn't necessarily meant for full production use.
func (s *service) ExcludeDependencySnapshots(ctx context.Context, req *proto.ExcludeDependencySnapshotsRequest) (*proto.ExcludeDependencySnapshotsResponse, error) {
	result, err := s.snapshotsSvc.ExcludeDependencySnapshots(ctx, req.RepositoryId, req.SnapshotIds)
	if err != nil {
		return nil, twirp.WrapError(
			twirp.NewError(twirp.Internal, "excluding dependency snapshots"),
			errors.Wrapf(err, "in ExcludeDependencySnapshot"))
	}

	return &proto.ExcludeDependencySnapshotsResponse{ExcludedSnapshotIds: result}, nil
}

type diffableSnapshots struct {
	baseSnaps []*interfaces.Snapshot
	headSnaps []*interfaces.Snapshot
	base      string
	head      string
}

func (s *service) getDiffableSnapshots(ctx context.Context, repositoryID uint64, base, head string) (diffableSnapshots, error) {
	result := diffableSnapshots{base: base, head: head}

	baseSnaps, err := s.snapshotsSvc.QueryCompleteSnapshots(ctx, repositoryID, base)
	if err != nil {
		return result, twirp.WrapError(
			twirp.NewError(twirp.Internal, "getting base snapshots"),
			errors.Wrapf(err, "in getDiffableSnapshots"))
	}

	result.baseSnaps = baseSnaps

	headSnaps, err := s.snapshotsSvc.QueryCompleteSnapshots(ctx, repositoryID, head)
	if err != nil {
		return result, twirp.WrapError(
			twirp.NewError(twirp.Internal, "getting head snapshots"),
			errors.Wrapf(err, "in getDiffableSnapshots"))
	}

	result.headSnaps = headSnaps

	return result, nil
}

func (s *service) reportDiffableSnapsMetrics(diffableSnaps diffableSnapshots) {
	s.statter.Distribution("dependency_review.diffable_manifests.total_snapshots", stats.Tags{}, float64(len(diffableSnaps.baseSnaps)+len(diffableSnaps.headSnaps)))

	if len(diffableSnaps.baseSnaps) == len(diffableSnaps.headSnaps) {
		s.statter.Counter("dependency_review.diffable_manifests.exact_match", stats.Tags{"result": "true"}, 1)
		return
	} else {
		s.statter.Counter("dependency_review.diffable_manifests.exact_match", stats.Tags{"result": "false"}, 1)
	}

	surplusBaseSnaps := len(diffableSnaps.baseSnaps) - len(diffableSnaps.headSnaps)
	surplusHeadSnaps := len(diffableSnaps.headSnaps) - len(diffableSnaps.baseSnaps)

	if surplusBaseSnaps > 0 {
		s.statter.Distribution("dependency_review.diffable_manifests.surplus_base_snapshots", stats.Tags{}, float64(surplusBaseSnaps))
	}
	if surplusHeadSnaps > 0 {
		s.statter.Distribution("dependency_review.diffable_manifests.surplus_head_snapshots", stats.Tags{}, float64(surplusHeadSnaps))
	}
}

func validateDiffableSnapshots(ds diffableSnapshots) error {
	if len(ds.headSnaps) == 0 {
		return twirp.NotFoundError("no snapshots found for head commit "+ds.head).
			WithMeta("base_snapshots", strconv.Itoa(len(ds.baseSnaps)))
	}
	return nil
}

func (s *service) GetSnapshotDiff(ctx context.Context, req *proto.GetSnapshotDiffRequest) (*proto.GetSnapshotDiffResponse, error) {
	// Right now, "ENTERPRISE" means no historical snapshot storage, which means nothing to diff against.
	if os.Getenv("ENTERPRISE") == "true" {
		return nil, twirp.NewError(twirp.Unimplemented, "not implemented in GitHub Enterprise Server")
	}
	repositoryID := req.GetRepositoryId()
	if repositoryID == 0 {
		return nil, twirp.RequiredArgumentError("repository_id")
	}

	if len(req.GetBasehead()) == 0 {
		return nil, twirp.RequiredArgumentError("basehead")
	}

	baseHeadPattern := regexp.MustCompile(`^[a-f0-9]{40}\.\.\.[a-f0-9]{40}$`)
	if !baseHeadPattern.MatchString(req.GetBasehead()) {
		return nil, twirp.InvalidArgumentError("basehead", "must be of the form [a-f0-9]{40}...[a-f0-9]{40}")
	}

	baseHead := strings.Split(req.GetBasehead(), "...")
	base := baseHead[0]
	head := baseHead[1]

	diffableSnaps, err := s.getDiffableSnapshots(ctx, repositoryID, base, head)
	if err != nil {
		return nil, twirp.WrapError(
			twirp.NewError(twirp.Internal, "getting diffable snapshots"),
			errors.Wrapf(err, "in GetSnapshotDiff"))
	}
	s.reportDiffableSnapsMetrics(diffableSnaps)

	if err := validateDiffableSnapshots(diffableSnaps); err != nil {
		return nil, err
	}

	baseSnaps := diffableSnaps.baseSnaps
	headSnaps := diffableSnaps.headSnaps

	diff, err := interfaces.Diff(baseSnaps, headSnaps)
	if err != nil {
		return nil, twirp.WrapError(
			twirp.NewError(twirp.Internal, "diffing snapshots"),
			errors.Wrapf(err, "in GetSnapshotDiff"))
	}

	changes := make([]*proto.GetSnapshotDiffResponse_DependencyChange, len(diff))
	for i, change := range diff {
		var changeType proto.GetSnapshotDiffResponse_ChangeType
		switch change.ChangeType {
		case interfaces.ADDED:
			changeType = proto.GetSnapshotDiffResponse_ADDED
		case interfaces.REMOVED:
			changeType = proto.GetSnapshotDiffResponse_REMOVED
		}

		snapshotMeta := &proto.GetSnapshotDiffResponse_SnapshotMetadata{
			SnapshotId: change.SnapshotMeta.SnapshotID,
			Correlator: change.SnapshotMeta.Correlator,
			Detector:   change.SnapshotMeta.Detector,
		}

		var scope proto.GetSnapshotDiffResponse_Scope
		switch change.Scope {
		case interfaces.NoScope:
			scope = proto.GetSnapshotDiffResponse_NONE
		case interfaces.Runtime:
			scope = proto.GetSnapshotDiffResponse_RUNTIME
		case interfaces.Development:
			scope = proto.GetSnapshotDiffResponse_DEVELOPMENT
		default:
			return nil, twirp.NewError(twirp.Internal, "invalid scope")
		}

		changes[i] = &proto.GetSnapshotDiffResponse_DependencyChange{
			ChangeType:       changeType,
			SnapshotMetadata: snapshotMeta,
			Manifest:         change.Manifest,
			Ecosystem:        change.Ecosystem,
			Name:             change.Name,
			Version:          change.Version,
			PackageUrl:       change.PackageURL,
			Scope:            scope,
		}
	}

	response := &proto.GetSnapshotDiffResponse{
		DependencyChanges:     changes,
		BaseSnapshotsCompared: uint32(len(baseSnaps)),
		HeadSnapshotsCompared: uint32(len(headSnaps)),
	}

	return response, nil
}

func (s *service) GetSnapshotDiffStatus(ctx context.Context, req *proto.GetSnapshotDiffStatusRequest) (*proto.GetSnapshotDiffStatusResponse, error) {
	// Right now, "ENTERPRISE" means no historical snapshot storage, which means nothing to diff against.
	if os.Getenv("ENTERPRISE") == "true" {
		return nil, twirp.NewError(twirp.Unimplemented, "not implemented in GitHub Enterprise Server")
	}
	repositoryID := req.GetRepositoryId()
	if repositoryID == 0 {
		return nil, twirp.RequiredArgumentError("repository_id")
	}

	if len(req.GetBasehead()) == 0 {
		return nil, twirp.RequiredArgumentError("basehead")
	}

	baseHeadPattern := regexp.MustCompile(`^[a-f0-9]{40}\.\.\.[a-f0-9]{40}$`)
	if !baseHeadPattern.MatchString(req.GetBasehead()) {
		return nil, twirp.InvalidArgumentError("basehead", "must be of the form [a-f0-9]{40}...[a-f0-9]{40}")
	}

	baseHead := strings.Split(req.GetBasehead(), "...")
	base := baseHead[0]
	head := baseHead[1]

	baseCount, err := s.snapshotsSvc.CountCompleteSnapshotsForSHA(ctx, repositoryID, base)
	if err != nil {
		return nil, twirp.WrapError(
			twirp.NewError(twirp.Internal, "getting status of diffable snapshots"),
			errors.Wrapf(err, "in GetSnapshotDiffStatus"))
	}

	headCount, err := s.snapshotsSvc.CountCompleteSnapshotsForSHA(ctx, repositoryID, head)
	if err != nil {
		return nil, twirp.WrapError(
			twirp.NewError(twirp.Internal, "getting status of diffable snapshots"),
			errors.Wrapf(err, "in GetSnapshotDiffStatus"))
	}

	response := &proto.GetSnapshotDiffStatusResponse{
		BaseSnapshotCount: uint32(baseCount),
		HeadSnapshotCount: uint32(headCount),
		MissingDetectors:  []string{},
	}

	return response, nil
}
