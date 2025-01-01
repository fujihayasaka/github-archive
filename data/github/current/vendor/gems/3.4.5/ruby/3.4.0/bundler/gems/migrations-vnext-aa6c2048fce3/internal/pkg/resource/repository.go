package resource

import (
	"context"
	"fmt"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/migrations-vnext/internal/pkg/client"
	"github.com/github/migrations-vnext/internal/pkg/keys"
	octov1 "github.com/github/migrations-vnext/internal/pkg/octoshift/imports/v1"
	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
)

type repository struct {
	baseHandler
	pb             *v1.Repository
	key            keys.RepositoryKey
	importedResult *octov1.ImportRepositoryResponse
	adminUserID    int64
}

var _ handler = (*repository)(nil)

func newRepository(pb *v1.Repository, adminUserID int64, logger log.Logger) *repository {
	return &repository{
		baseHandler: baseHandler{logger},
		pb:          pb,
		adminUserID: adminUserID,
	}
}

func (r *repository) resourceID() string {
	return r.pb.ResourceId
}

func (r *repository) dependencies() (*transformedDeps, error) {
	k, err := keys.ToRepositoryKey(r.pb.ResourceId)
	if err != nil {
		return nil, fmt.Errorf("could not parse repo key: %w", err)
	}
	r.key = k
	deps := newTransformedDeps()
	deps.int64Deps.Add(k.OrganizationKey.String())
	return deps, nil
}

func (r *repository) load(ctx context.Context, importer client.Importer, resolved resolvedIDsByResource) error {
	if r.adminUserID == 0 {
		return fmt.Errorf("admin user id is required")
	}

	req := &octov1.ImportRepositoryRequest{
		OwnerId: resolved[r.key.OrganizationKey.String()].int64Val,
		Name:    r.key.Name,
		Visibility: func() octov1.RepositoryVisibility {
			if r.pb.GetIsPrivate() {
				return octov1.RepositoryVisibility_REPOSITORY_VISIBILITY_PRIVATE
			}
			return octov1.RepositoryVisibility_REPOSITORY_VISIBILITY_INTERNAL
		}(),
		UserId: r.adminUserID,
	}

	res, err := importer.ImportRepository(ctx, req)
	if err != nil {
		r.logger.WithError(err).Error("failed to import repo", kvp.Any("request", req))
		return fmt.Errorf("failed to load repo: %w", err)
	}
	r.importedResult = res

	return nil
}

func (r *repository) newResolvedIDs() resolvedIDsByResource {
	return resolvedIDsByResource{
		r.resourceID(): &transformedValues{
			int64Val: r.importedResult.Repository.Id,
			strVal:   r.importedResult.Repository.HttpUrl,
		},
	}
}
