package dependencies

import (
	"context"
	"time"

	"github.com/Masterminds/semver"
	"github.com/github/dependency-snapshots-api/internal/contextlogger"
	"github.com/github/dependency-snapshots-api/internal/features"
	"github.com/github/dependency-snapshots-api/internal/interfaces"
	"github.com/github/dependency-snapshots-api/pkg/proto"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	"github.com/package-url/packageurl-go"
	"github.com/pkg/errors"
	"github.com/twitchtv/twirp"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/trace"
	"google.golang.org/protobuf/types/known/timestamppb"
)

const RootAncestorsDarkShipFeatureFlag = "dependency_graph_snapshot_root_ancestors_dark_ship"

// service holds the methods for our Twirp Server as well as a few dependencies.
type service struct {
	dependenciesSvc interfaces.DependenciesService
	statter         stats.Client
	features        features.Client
}

// CreateTwirpServer creates a new TwirpServer instance that adheres to DependenciesService's API.
func CreateTwirpServer(hooks *twirp.ServerHooks, statter stats.Client, features features.Client, dependenciesSvc interfaces.DependenciesService) proto.TwirpServer {
	service := CreateService(statter, features, dependenciesSvc)
	return proto.NewDependenciesServiceServer(service, hooks)
}

// CreateService creates a new proto.DependenciesService.
func CreateService(statter stats.Client, features features.Client, dependenciesSvc interfaces.DependenciesService) proto.DependenciesService {
	service := &service{
		dependenciesSvc: dependenciesSvc,
		statter:         statter,
		features:        features,
	}

	return service
}

func DependencyScopeToTwirp(scope interfaces.DependencyScope) proto.Manifest_Dependency_Scope {
	switch scope {
	case interfaces.NoScope:
		return proto.Manifest_Dependency_SCOPE_NONE
	case interfaces.Runtime:
		return proto.Manifest_Dependency_SCOPE_RUNTIME
	case interfaces.Development:
		return proto.Manifest_Dependency_SCOPE_DEVELOPMENT
	default:
		return proto.Manifest_Dependency_SCOPE_NONE
	}
}

func DependencyScopeFromTwirp(scope proto.Manifest_Dependency_Scope) interfaces.DependencyScope {
	switch scope {
	case proto.Manifest_Dependency_SCOPE_NONE:
		return interfaces.NoScope
	case proto.Manifest_Dependency_SCOPE_RUNTIME:
		return interfaces.Runtime
	case proto.Manifest_Dependency_SCOPE_DEVELOPMENT:
		return interfaces.Development
	default:
		return interfaces.NoScope
	}
}

func DependencyRelationshipToTwirp(relationship interfaces.DependencyRelationship) proto.Relationship {
	switch relationship {
	case interfaces.Direct:
		return proto.Relationship_RELATIONSHIP_DIRECT
	case interfaces.Indirect:
		return proto.Relationship_RELATIONSHIP_TRANSITIVE
	default:
		return proto.Relationship_RELATIONSHIP_UNKNOWN
	}
}

func DependencyRelationshipFromTwirp(relationship proto.Relationship) interfaces.DependencyRelationship {
	switch relationship {
	case proto.Relationship_RELATIONSHIP_DIRECT:
		return interfaces.Direct
	case proto.Relationship_RELATIONSHIP_TRANSITIVE:
		return interfaces.Indirect
	default:
		return interfaces.NoRelationship
	}
}

// We'll limit the root ancestor calculation to finish by this time.
// 7 seconds is a pretty long time. Clients will get a 500 after about 10 seconds,
// but given that this API is consumed by other internal APIs that need to do some additional work,
// it would be good to return in more like 3-4 seconds.
// It may make sense to adjust this in the future, but I'd rather adjust it down than up.
const MAX_GET_DEPENDENCIES_FOR_REPOSITORY_ANCESTORS_TIME = 7 * time.Second

func (s *service) GetDependenciesForRepository(ctx context.Context, req *proto.GetDependenciesForRepositoryRequest) (*proto.GetDependenciesForRepositoryResponse, error) {
	ctx, ender, span := contextlogger.LogStartAndStop(ctx, "GetDependenciesForRepository", "GetDependenciesForRepository",
		kvp.Uint64("gh.repo.id", req.RepositoryId),
	)
	defer ender()
	var mode interfaces.SnapshotQueryMode
	if req.IncludeInternalSnapshots {
		mode = interfaces.IncludeInternal
	} else {
		mode = interfaces.DefaultQueryMode
	}

	startTime := time.Now()
	deadline := startTime.Add(MAX_GET_DEPENDENCIES_FOR_REPOSITORY_ANCESTORS_TIME)
	ctx, cancelCtx := context.WithDeadline(ctx, deadline)
	defer cancelCtx()

	snapshots, err := s.dependenciesSvc.CanonicalSnapshotsForRepository(ctx, req.GetRepositoryId(), mode)
	if err != nil {
		return nil, twirp.WrapError(
			twirp.NewError(twirp.Internal, "querying GetDependenciesForRepository"),
			errors.Wrapf(err, "in GetDependenciesForRepository"))
	}

	return s.buildGetDependenciesForRepositoryResponse(ctx, req, snapshots, span, startTime)
}

func (s *service) buildGetDependenciesForRepositoryResponse(ctx context.Context, req *proto.GetDependenciesForRepositoryRequest, snapshots []*interfaces.Snapshot, span trace.Span, startTime time.Time) (*proto.GetDependenciesForRepositoryResponse, error) {
	manifests := interfaces.CombineManifests(ctx, snapshots)

	relationshipFilter := req.RelationshipFilter
	includeDependency := func(dependency *interfaces.DependencyNode) bool {
		if relationshipFilter == nil {
			return true
		}
		if *relationshipFilter == proto.Relationship_RELATIONSHIP_DIRECT {
			return dependency.Relationship == interfaces.Direct
		}
		if *relationshipFilter == proto.Relationship_RELATIONSHIP_TRANSITIVE {
			return dependency.Relationship == interfaces.Indirect
		}
		if *relationshipFilter == proto.Relationship_RELATIONSHIP_UNKNOWN {
			return dependency.Relationship == interfaces.NoRelationship
		}
		// should be unreachable, but just in case
		return true
	}

	response := proto.GetDependenciesForRepositoryResponse{}

	if len(manifests) > 0 {
		span.AddEvent("number of manifests", trace.WithAttributes(attribute.Int("nresults", len(manifests))))

		response.AllManifests = make([]*proto.Manifest, 0, len(manifests))
		for _, manifest := range manifests {
			dependencies := map[string]*proto.Manifest_Dependency{}
			manifestRootAncestors := interfaces.RootAncestorMap{}
			if req.IncludeRootAncestors {
				var err error
				manifestRootAncestors, err = interfaces.GetRootAncestors(ctx, req.RepositoryId, manifest)
				if err != nil {
					// This indicates a timeout in GetRootAncestors.
					// We can and should continue to return the dependencies, but the response
					// will be missing root ancestors.
					contextlogger.Warn(ctx, "GetRootAncestors canceled. Returning response without root ancestors",
						kvp.Uint64("gh.repo.id", req.RepositoryId),
						kvp.Duration("elapsed", time.Since(startTime)),
					)
					s.statter.Counter("dependencies.GetRootAncestors.canceled", nil, 1)
				}
			}

			for dependencyKey, dependency := range manifest.Resolved {
				if includeDependency(dependency) {
					twirpRootAncestors := getTwirpRootAncestors(manifestRootAncestors, dependency)
					dependencies[dependencyKey] = &proto.Manifest_Dependency{
						PackageUrl:    dependency.PackageURL,
						Dependencies:  dependency.Dependencies,
						Scope:         DependencyScopeToTwirp(dependency.Scope),
						Relationship:  DependencyRelationshipToTwirp(dependency.Relationship),
						RootAncestors: twirpRootAncestors,
					}
				}
			}

			response.AllManifests = append(response.AllManifests, &proto.Manifest{
				FilePath:     manifest.File.SourceLocation,
				Dependencies: dependencies,
				Name:         manifest.Name,
				SnapshotId:   manifest.SnapshotID,
			})
		}

		response.Manifests = make(map[string]*proto.Manifest, len(manifests))

		// The original response.Manifests was keyed on manifest name, but we've
		// started keying on the file path instead. response.Manifests should
		// really be deprecated anyway, because the clients should all be using
		// AllManifests instead now.
		// For consistency's sake if there are any clients still using it,
		// we'll keep response.Manifests keyed on the name.
		for _, manifest := range response.AllManifests {
			response.Manifests[manifest.Name] = manifest
		}

		response.Snapshots = make(map[uint64]*proto.GetDependenciesForRepositoryResponse_Snapshot, len(snapshots))
		for _, snapshot := range snapshots {
			response.Snapshots[snapshot.ID] = &proto.GetDependenciesForRepositoryResponse_Snapshot{
				Detector: &proto.GetDependenciesForRepositoryResponse_Snapshot_DetectorMetadata{
					Name: snapshot.Detector.Name,
				},
				Scanned: timestamppb.New(snapshot.Scanned),
			}
		}
	}
	return &response, nil
}

func getTwirpRootAncestors(ancestorMap interfaces.RootAncestorMap, dependency *interfaces.DependencyNode) []*proto.RootAncestor {
	var twirpRootAncestors []*proto.RootAncestor
	if rootAncestors, ok := ancestorMap[dependency]; ok {
		for rootAncestor := range rootAncestors {
			twirpRootAncestors = append(twirpRootAncestors, &proto.RootAncestor{
				PackageName:  rootAncestor.PackageName,
				Requirements: rootAncestor.Requirements,
				Relationship: proto.AncestorRelationship(rootAncestor.AncestorRelationship),
			})
		}
	}

	return twirpRootAncestors
}

func (s *service) HasManifests(ctx context.Context, req *proto.HasManifestsRequest) (*proto.HasManifestsResponse, error) {
	has, err := s.dependenciesSvc.HasManifests(ctx, req.GetRepositoryId())
	if err != nil {
		return nil, twirp.WrapError(
			twirp.NewError(twirp.Internal, "querying HasManifests"),
			errors.Wrapf(err, "in HasManifests"))
	}

	return &proto.HasManifestsResponse{
		HasManifests: has,
	}, nil
}

func (s *service) RepositoriesContainingDependency(ctx context.Context, req *proto.RepositoriesContainingDependencyRequest) (*proto.RepositoriesContainingDependencyResponse, error) {
	var mode interfaces.SnapshotQueryMode

	_, err := packageurl.FromString(req.GetBasePurl())
	if err != nil {
		return nil, twirp.NewError(twirp.Malformed, "invalid base purl "+req.GetBasePurl())
	}

	_, err = semver.NewConstraint(req.GetVersionRange())
	if err != nil {
		return nil, twirp.NewError(twirp.Malformed, "invalid version range "+req.GetVersionRange())
	}

	repoIDs, err := s.dependenciesSvc.RepositoriesContainingDependency(ctx, req.GetBasePurl(), req.GetVersionRange(), mode)
	if err != nil {
		return nil, twirp.WrapError(
			twirp.NewError(twirp.Internal, "querying RepositoriesContainingDependency"),
			errors.Wrapf(err, "in RepositoriesContainingDependency"))
	}

	return &proto.RepositoriesContainingDependencyResponse{
		RepositoryIds: repoIDs,
	}, nil
}
