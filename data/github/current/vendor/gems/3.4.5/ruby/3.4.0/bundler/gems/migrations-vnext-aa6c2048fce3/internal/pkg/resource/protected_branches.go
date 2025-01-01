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

type protectedBranch struct {
	baseHandler
	pb             *v1.ProtectedBranch
	importedResult *octov1.ImportProtectedBranchResponse
}

var _ handler = (*protectedBranch)(nil)

func newProtectedBranch(pb *v1.ProtectedBranch, logger log.Logger) *protectedBranch {
	return &protectedBranch{
		baseHandler: baseHandler{logger},
		pb:          pb,
	}
}

func (p *protectedBranch) resourceID() string {
	return p.pb.ResourceId
}

func (p *protectedBranch) dependencies() (*transformedDeps, error) {
	deps := newTransformedDeps()
	deps.int64Deps.Add(p.pb.RepositoryResourceId)
	return deps, nil
}

func (p *protectedBranch) load(ctx context.Context, importer client.Importer, resolved resolvedIDsByResource) error {
	repoID := resolved[p.pb.RepositoryResourceId].int64Val

	req := &octov1.ImportProtectedBranchRequest{
		RepositoryId:                   repoID,
		Name:                           p.pb.Name,
		RequiresApprovingReviews:       p.pb.RequiresApprovingReviews,
		RequiredApprovingReviewCount:   p.pb.RequiredApprovingReviewCount,
		RequiresCommitSignatures:       p.pb.RequiresCommitSignatures,
		RequiresLinearHistory:          p.pb.RequiresLinearHistory,
		AllowsForcePushes:              p.pb.AllowsForcePushes,
		AllowsDeletions:                p.pb.AllowsDeletions,
		IsAdminEnforced:                p.pb.IsAdminEnforced,
		RequiresStatusChecks:           p.pb.RequiresStatusChecks,
		RequiresStrictStatusChecks:     p.pb.RequiresStrictStatusChecks,
		RequiresCodeOwnerReviews:       p.pb.RequiresCodeOwnerReviews,
		DismissesStaleReviews:          p.pb.DismissesStaleReviews,
		RestrictsReviewDismissals:      p.pb.RestrictsReviewDismissals,
		RestrictsPushes:                p.pb.RestrictsPushes,
		RequiredStatusCheckContexts:    p.pb.RequiredStatusCheckContexts,
		RequiresReviewThreadResolution: p.pb.RequiresReviewThreadResolution,
		RequireLastPushApproval:        p.pb.RequireLastPushApproval,
	}
	res, err := importer.ImportProtectedBranch(ctx, req)
	if err != nil {
		p.logger.WithError(err).Error("failed to import protected branch", kvp.Any("request", req))
		return fmt.Errorf("failed to load protected branch: %w", err)
	}
	p.importedResult = res
	return nil
}

func (p *protectedBranch) newResolvedIDs() resolvedIDsByResource {
	return resolvedIDsByResource{
		p.resourceID(): &transformedValues{
			int64Val: p.importedResult.ProtectedBranch.Id,
		},
	}
}
