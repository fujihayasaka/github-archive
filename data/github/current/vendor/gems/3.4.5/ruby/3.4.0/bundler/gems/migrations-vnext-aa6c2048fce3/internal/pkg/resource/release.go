package resource

import (
	"context"
	"fmt"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/migrations-vnext/internal/pkg/client"
	octov1 "github.com/github/migrations-vnext/internal/pkg/octoshift/imports/v1"
	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
)

type release struct {
	baseHandler
	pb         *v1.Release
	importedID int64
}

var _ handler = (*release)(nil)

func newRelease(r *v1.Release, l log.Logger) *release {
	return &release{
		baseHandler: baseHandler{l},
		pb:          r,
	}
}

func (r *release) resourceID() string {
	return r.pb.ResourceId
}

func (r *release) dependencies() (*transformedDeps, error) {
	deps := newTransformedDeps()
	deps.int64Deps.Add(r.pb.RepositoryResourceId)
	deps.strDeps.Add(r.pb.UserResourceId)
	return deps, nil
}

func (r *release) load(ctx context.Context, importer client.Importer, resolved resolvedIDsByResource) error {
	var state octov1.ReleaseState
	switch r.pb.State {
	case "draft":
		state = octov1.ReleaseState_RELEASE_STATE_DRAFT
	case "published":
		state = octov1.ReleaseState_RELEASE_STATE_PUBLISHED
	default:
		return fmt.Errorf("invalid release state: %s", r.pb.State)
	}

	req := &octov1.ImportReleaseRequest{
		RepositoryId:    resolved[r.pb.RepositoryResourceId].int64Val,
		AuthorLogin:     resolved[r.pb.UserResourceId].strVal,
		Name:            r.pb.Name,
		TagName:         r.pb.TagName,
		Body:            r.pb.Body,
		State:           state,
		PendingTag:      r.pb.PendingTag,
		IsPreRelease:    r.pb.IsPreRelease,
		TargetCommitish: r.pb.TargetCommitish,
		PublishedAt:     r.pb.PublishedAt,
		CreatedAt:       r.pb.CreatedAt,
	}

	res, err := importer.ImportRelease(ctx, req)
	if err != nil {
		r.logger.WithError(err).Error("failed to import release", kvp.Any("request", req))
		return fmt.Errorf("failed to load release: %w", err)
	}
	r.importedID = res.Release.Id
	return nil
}

func (r *release) newResolvedIDs() resolvedIDsByResource {
	return resolvedIDsByResource{
		r.resourceID(): &transformedValues{
			int64Val: r.importedID,
		},
	}
}
