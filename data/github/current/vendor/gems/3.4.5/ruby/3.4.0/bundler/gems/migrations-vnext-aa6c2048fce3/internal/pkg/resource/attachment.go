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

// TODO This struct does not actually attempt to upload resources at this point, but does
// create the storage policy required to upload.
type attachment struct {
	baseHandler
	pb *v1.Attachment
}

var _ handler = (*attachment)(nil)

func newAttachment(pb *v1.Attachment, logger log.Logger) *attachment {
	return &attachment{
		baseHandler: baseHandler{logger},
		pb:          pb,
	}
}

func (a *attachment) resourceID() string {
	return a.pb.ResourceId
}

func (a *attachment) dependencies() (*transformedDeps, error) {
	deps := newTransformedDeps()
	deps.int64Deps.Add(a.pb.RepositoryId)
	return deps, nil
}

func (a *attachment) load(ctx context.Context, importer client.Importer, resolved resolvedIDsByResource) error {
	req := &octov1.CreateAssetStoragePolicyRequest{
		RepositoryId: resolved[a.pb.RepositoryId].int64Val,
		Name:         a.pb.Name,
		Size:         100,
		ContentType:  a.pb.ContentType,
		ActorId:      2, // This actorID cannot be a mannequin and should be the user_id of the user performing the migration.
		AssetType:    octov1.AssetType_ASSET_TYPE_AUTO,
	}

	_, err := importer.CreateAssetStoragePolicy(ctx, req)
	if err != nil {
		a.logger.WithError(err).Error("failed to import attachment", kvp.Any("request", req))
		return fmt.Errorf("failed to load attachment: %w", err)
	}
	// TODO Upload asset using the storage policy.
	// TODO Logic will be required to mark asset uploaded in monolith in some environments
	return nil
}

func (a *attachment) newResolvedIDs() resolvedIDsByResource {
	// TODO In codespaces storagePolicy.AssetUrl will be empty, the url cannot be known until successful upload to Alambic.
	// Rewrite blank urls to the ghost avatar image just to have something to render.
	assetURL := a.pb.AssetUrl
	if assetURL == "" {
		assetURL = "http://alambic.github.localhost/avatars/u/1"
	}
	return resolvedIDsByResource{
		a.resourceID(): &transformedValues{
			strVal: assetURL,
		},
	}
}
