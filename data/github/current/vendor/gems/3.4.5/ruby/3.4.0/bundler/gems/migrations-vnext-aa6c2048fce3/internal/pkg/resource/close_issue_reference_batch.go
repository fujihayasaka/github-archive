package resource

import (
	"context"
	"fmt"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/migrations-vnext/internal/pkg/client"
	octov1 "github.com/github/migrations-vnext/internal/pkg/octoshift/imports/v1"
	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
)

type closeIssueReferenceBatch struct {
	baseBatchHandler
	pb        *v1.CloseIssueReferenceBatch
	failedIDs idSet
}

var _ batchHandler = (*closeIssueReferenceBatch)(nil)

func newCloseIssueReferenceBatch(pb *v1.CloseIssueReferenceBatch, logger log.Logger) *closeIssueReferenceBatch {
	return &closeIssueReferenceBatch{
		baseBatchHandler: baseBatchHandler{},
		pb:               pb,
	}
}

func (b *closeIssueReferenceBatch) batchID() string {
	return b.pb.ResourceId
}
func (b *closeIssueReferenceBatch) itemIDs() []string {
	var ids []string
	for _, ref := range b.pb.CloseIssueReferences {
		ids = append(ids, ref.ResourceId)
	}
	return ids
}

func (b *closeIssueReferenceBatch) dependencies(_ idSet) (*transformedDeps, error) {
	deps := newTransformedDeps()
	for _, ref := range b.pb.CloseIssueReferences {
		deps.int64Deps.Add(ref.PullRequestResourceId, ref.IssueResourceId)
	}
	return deps, nil
}

func (b *closeIssueReferenceBatch) load(ctx context.Context, importer client.Importer, loaded idSet, resolved resolvedIDsByResource) error {
	var refs []*octov1.CloseIssueReference
	for _, ref := range b.pb.CloseIssueReferences {
		if _, ok := loaded[ref.ResourceId]; ok {
			continue
		}
		refs = append(refs, &octov1.CloseIssueReference{
			PullRequestId: resolved[ref.PullRequestResourceId].int64Val,
			IssueId:       resolved[ref.IssueResourceId].int64Val,
		})
	}
	if len(refs) == 0 {
		return nil
	}

	req := &octov1.ImportCloseIssueReferencesRequest{
		CloseIssueReferences: refs,
	}

	res, err := importer.ImportCloseIssueReferences(ctx, req)
	if err != nil {
		return fmt.Errorf("failed to import close issue references: %w", err)
	}

	if len(res.BatchValidationErrors) == 0 {
		return nil
	}

	items, err := toFailedItems(res.BatchValidationErrors, b.pb.CloseIssueReferences)
	if err != nil {
		return fmt.Errorf("failed to convert to failed items list: %w", err)
	}
	for _, e := range items {
		b.failedIDs[e.ResourceId] = struct{}{}
	}

	return &PartialBatchError{toFailedErrors(res.BatchValidationErrors), b.failedIDs}
}

func (b *closeIssueReferenceBatch) newResolvedIDs() resolvedIDsByResource {
	// CloseIssueReferenceBatch contains only virtual resources that do not have IDs of their own and should not be referenced.
	return make(resolvedIDsByResource)
}
