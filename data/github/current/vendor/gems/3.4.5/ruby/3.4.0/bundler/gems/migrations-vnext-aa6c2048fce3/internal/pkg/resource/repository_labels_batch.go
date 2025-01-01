package resource

import (
	"context"
	"fmt"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/migrations-vnext/internal/pkg/client"
	octov1 "github.com/github/migrations-vnext/internal/pkg/octoshift/imports/v1"
	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
)

type repositoryLabelsBatch struct {
	baseBatchHandler
	pb        *v1.RepositoryLabelsBatch
	failedIDs idSet
}

var _ batchHandler = (*repositoryLabelsBatch)(nil)

func newRepositoryLabelsBatch(pb *v1.RepositoryLabelsBatch, logger log.Logger) *repositoryLabelsBatch {
	return &repositoryLabelsBatch{
		baseBatchHandler: baseBatchHandler{},
		pb:               pb,
		failedIDs:        make(idSet),
	}
}

func (r *repositoryLabelsBatch) batchID() string {
	return r.pb.ResourceId
}

func (r *repositoryLabelsBatch) itemIDs() []string {
	var ids []string
	for _, l := range r.pb.Labels {
		ids = append(ids, l.ResourceId)
	}
	return ids
}

func (r *repositoryLabelsBatch) dependencies(_ idSet) (*transformedDeps, error) {
	deps := newTransformedDeps()
	deps.int64Deps.Add(r.pb.RepositoryId)
	return deps, nil
}

func (r *repositoryLabelsBatch) load(ctx context.Context, importer client.Importer, loaded idSet, resolved resolvedIDsByResource) error {
	// Add the events to the batch
	var labels []*octov1.Label
	for _, l := range r.pb.Labels {
		if _, ok := loaded[l.ResourceId]; ok {
			continue
		}
		labels = append(labels, &octov1.Label{
			Name:        l.Name,
			Color:       l.Color,
			Description: l.Description,
		})
	}

	// If there are no events, return early
	if len(labels) == 0 {
		return nil
	}

	req := &octov1.ImportLabelsRequest{
		RepositoryId: resolved[r.pb.RepositoryId].int64Val,
		Labels:       labels,
	}

	res, err := importer.ImportLabels(ctx, req)
	if err != nil {
		return fmt.Errorf("failed to import repository labels: %w", err)
	}

	// If there are no batch validation errors, we are done
	if len(res.BatchValidationErrors) == 0 {
		return nil
	}

	// Some events failed to be imported, return a partial batch error containing the validation errors
	// and the IDs of the items that failed
	items, err := toFailedItems(res.BatchValidationErrors, r.pb.Labels)
	if err != nil {
		return fmt.Errorf("failed to get failed indices: %w", err)
	}
	for _, e := range items {
		r.failedIDs[e.ResourceId] = struct{}{}
	}
	return &PartialBatchError{toFailedErrors(res.BatchValidationErrors), r.failedIDs}
}

func (r *repositoryLabelsBatch) newResolvedIDs() resolvedIDsByResource {
	depVals := make(resolvedIDsByResource)
	for _, l := range r.pb.Labels {
		if _, ok := r.failedIDs[l.ResourceId]; ok {
			continue
		}
		depVals[l.ResourceId] = &transformedValues{strVal: l.Name}
	}
	return depVals
}
