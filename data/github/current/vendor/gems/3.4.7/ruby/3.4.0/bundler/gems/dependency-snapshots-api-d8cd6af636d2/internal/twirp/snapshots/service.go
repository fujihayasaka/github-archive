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

	"github.com/github/dependency-snapshots-api/internal/contextlogger"
	"github.com/github/dependency-snapshots-api/internal/features"
	"github.com/github/dependency-snapshots-api/internal/interfaces"
	"github.com/github/dependency-snapshots-api/pkg/proto"
	"github.com/github/github-telemetry-go/kvp"
	stats "github.com/github/go-stats"

	"github.com/pkg/errors"
	"github.com/twitchtv/twirp"
	"google.golang.org/protobuf/types/known/timestamppb"
)

// service holds the methods for our Twirp Server as well as a few dependencies.
type service struct {
	snapshotsSvc interfaces.SnapshotsService
	statter      stats.Client
	features     features.Client
}

// CreateTwirpServer creates a new TwirpServer instance that adheres to SnapshotsService's API.
func CreateTwirpServer(hooks *twirp.ServerHooks, statter stats.Client, features features.Client, snapshotSvc interfaces.SnapshotsService) proto.TwirpServer {
	server := CreateService(statter, features, snapshotSvc)
	return proto.NewSnapshotsServiceServer(server, hooks)
}

// CreateService creates a new proto.SnapshotsService.
func CreateService(statter stats.Client, features features.Client, snapshotSvc interfaces.SnapshotsService) proto.SnapshotsService {
	service := &service{
		snapshotsSvc: snapshotSvc,
		statter:      statter,
		features:     features,
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

	if err := validatePurls(ctx, &snapshot); err != nil {
		return &proto.CreateDependencySnapshotResponse{
			SnapshotId: 0,
			CreatedAt:  nil,
			Result:     proto.CreateDependencySnapshotResponse_INVALID,
			Message:    "Invalid package url.",
		}, twirp.NewError(twirp.Malformed, fmt.Sprintf("invalid package url: %v", err))
	}

	// inject repo ID included in request and validated upstream in the monolith
	snapshot.RepositoryID = req.GetRepositoryId()
	snapID, createdAt, result, err := s.snapshotsSvc.StoreSnapshot(ctx, &snapshot)
	if err != nil {
		contextlogger.Error(ctx, "CreateDependencySnapshot: validating or storing snapshot", kvp.String("exception.message", err.Error()))
		return nil, twirp.WrapError(
			twirp.NewError(twirp.Internal, "validating or storing snapshot"),
			errors.Wrapf(err, "in CreateDependencySnapshot"))
	}

	autoSubmission := strconv.FormatBool(snapshot.IsAutoSubmission())
	s.statter.Counter("create_dependency_snapshot.snapshot", stats.Tags{
		"auto_submission": autoSubmission,
	}, 1)
	for _, manifest := range snapshot.Manifests {
		manifestType := interfaces.InferManifestType(manifest)
		s.statter.Counter("create_dependency_snapshot.manifest", stats.Tags{
			"manifest_type":   manifestType,
			"auto_submission": autoSubmission,
		}, 1)
	}

	switch result {
	case interfaces.AcceptedNonDefaultBranch:
		return &proto.CreateDependencySnapshotResponse{
			SnapshotId: snapID,
			CreatedAt:  timestamppb.New(createdAt),
			Result:     proto.CreateDependencySnapshotResponse_ACCEPTED,
			Message:    "The snapshot was accepted, but it is not for the default branch. It will not update dependency results for the repository.",
		}, nil
	case interfaces.AcceptedHistorical:
		return &proto.CreateDependencySnapshotResponse{
			SnapshotId: snapID,
			CreatedAt:  timestamppb.New(createdAt),
			Result:     proto.CreateDependencySnapshotResponse_ACCEPTED,
			Message:    "The snapshot was accepted, but it is superseded by a newer snapshot from the same detector and correlator. It will not update dependency results for the repository.",
		}, nil
	case interfaces.AcceptedCanonical:
		return &proto.CreateDependencySnapshotResponse{
			SnapshotId: snapID,
			CreatedAt:  timestamppb.New(createdAt),
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
	hasManifests bool
	baseSnaps    []*interfaces.Snapshot
	headSnaps    []*interfaces.Snapshot
	base         string
	head         string
}

func (s *service) getDiffableSnapshots(ctx context.Context, repositoryID uint64, base, head string) (diffableSnapshots, error) {
	result := diffableSnapshots{base: base, head: head}
	hasManifests, err := s.snapshotsSvc.HasManifests(ctx, repositoryID)
	if err != nil {
		return result, twirp.WrapError(
			twirp.NewError(twirp.Internal, "checking for manifests"),
			errors.Wrapf(err, "in getDiffableSnapshots"))
	}

	result.hasManifests = hasManifests

	if !hasManifests {
		return result, nil
	}

	baseSnaps, err := s.snapshotsSvc.QuerySnapshots(ctx, repositoryID, interfaces.SnapshotsQuery{SHA: base})
	if err != nil {
		return result, twirp.WrapError(
			twirp.NewError(twirp.Internal, "getting base snapshots"),
			errors.Wrapf(err, "in getDiffableSnapshots"))
	}

	result.baseSnaps = baseSnaps

	headSnaps, err := s.snapshotsSvc.QuerySnapshots(ctx, repositoryID, interfaces.SnapshotsQuery{SHA: head})
	if err != nil {
		return result, twirp.WrapError(
			twirp.NewError(twirp.Internal, "getting head snapshots"),
			errors.Wrapf(err, "in getDiffableSnapshots"))
	}

	result.headSnaps = headSnaps

	return result, nil
}

func (s *service) reportDiffableSnapsMetrics(ctx context.Context, diffableSnaps diffableSnapshots) {
	if diffableSnaps.hasManifests {
		s.statter.Counter("dependency_review.diffable_manifests.has_manifests", stats.Tags{"result": "true"}, 1)
	} else {
		s.statter.Counter("dependency_review.diffable_manifests.has_manifests", stats.Tags{"result": "false"}, 1)
		return
	}

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
			WithMeta("has_manifests", strconv.FormatBool(ds.hasManifests)).
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
	s.reportDiffableSnapsMetrics(ctx, diffableSnaps)

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

	baseCount, err := s.snapshotsSvc.CountSnapshotsForSHA(ctx, repositoryID, interfaces.SnapshotsQuery{SHA: base})
	if err != nil {
		return nil, twirp.WrapError(
			twirp.NewError(twirp.Internal, "getting status of diffable snapshots"),
			errors.Wrapf(err, "in GetSnapshotDiffStatus"))
	}

	headCount, err := s.snapshotsSvc.CountSnapshotsForSHA(ctx, repositoryID, interfaces.SnapshotsQuery{SHA: head})
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
