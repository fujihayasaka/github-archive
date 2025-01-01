package resource

import (
	"context"
	"fmt"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/migrations-vnext/internal/pkg/assets"
	"github.com/github/migrations-vnext/internal/pkg/blobstore"
	"github.com/github/migrations-vnext/internal/pkg/client"
	octov1 "github.com/github/migrations-vnext/internal/pkg/octoshift/imports/v1"
	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
)

type releaseAsset struct {
	baseHandler
	pb                *v1.ReleaseAsset
	intermediateStore *blobstore.Store
	uploader          assets.Uploader
}

var _ handler = (*releaseAsset)(nil)

func newReleaseAsset(r *v1.ReleaseAsset, l log.Logger, store *blobstore.Store, uploader assets.Uploader) *releaseAsset {
	return &releaseAsset{
		baseHandler:       baseHandler{l},
		pb:                r,
		intermediateStore: store,
		uploader:          uploader,
	}
}

func (r *releaseAsset) resourceID() string {
	return r.pb.ResourceId
}

func (r *releaseAsset) dependencies() (*transformedDeps, error) {
	deps := newTransformedDeps()
	deps.int64Deps.Add(r.pb.ReleaseResourceId)
	deps.int64Deps.Add(r.pb.RepositoryResourceId)
	return deps, nil
}

func (r *releaseAsset) load(ctx context.Context, importer client.Importer, resolved resolvedIDsByResource) error {
	req := &octov1.CreateAssetStoragePolicyRequest{
		RepositoryId: resolved[r.pb.RepositoryResourceId].int64Val,
		Name:         r.pb.FileName,
		Size:         r.pb.Size,
		ContentType:  r.pb.ContentType,
		ActorId:      2, // resolved[r.pb.UserResourceId].int64Val, we cannot use mannequins.
		ReleaseId:    resolved[r.pb.ReleaseResourceId].int64Val,
		AssetType:    octov1.AssetType_ASSET_TYPE_RELEASE_ASSET,
	}

	policy, err := importer.CreateAssetStoragePolicy(ctx, req)
	if err != nil {
		r.logger.WithError(err).Error("failed to create release asset storage policy", kvp.Any("request", req))
		return fmt.Errorf("failed to load release asset: %w", err)
	}

	headers := map[string]string{}
	for _, h := range policy.Headers {
		headers[h.Key] = h.Value
	}
	formData := map[string]string{}
	for _, fd := range policy.FormData {
		formData[fd.Key] = fd.Value
	}
	stream, err := r.intermediateStore.GetBlobStream(ctx, r.pb.BlobKey)
	if err != nil {
		r.logger.WithError(err).Error("failed to get intermediate store blob stream", kvp.Any("blob-key", r.pb.BlobKey))
		return fmt.Errorf("failed to get intermediate store blob stream: %w", err)
	}
	defer stream.Close()

	_, err = r.uploader.PostMultipart(ctx, headers, formData, stream, policy.UploadUrl, r.pb.FileName)
	if err != nil {
		r.logger.WithError(err).Error("failed to upload release asset", kvp.Any("upload-url", policy.UploadUrl))
		return fmt.Errorf("failed to upload release asset: %w", err)
	}

	// TODO Logic will be required to mark asset uploaded in monolith in environments that don't use Alambic as the storage backend.
	return nil
}
