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

type issueLabelsBatch struct {
	baseHandler
	pb  *v1.IssueLabelsBatch
	key keys.IssueKey
}

var _ handler = (*issueLabelsBatch)(nil)

func newIssueLabelsBatch(pb *v1.IssueLabelsBatch, logger log.Logger) *issueLabelsBatch {
	return &issueLabelsBatch{
		baseHandler: baseHandler{logger},
		pb:          pb,
	}
}

func (i *issueLabelsBatch) resourceID() string {
	return i.pb.ResourceId
}

func (i *issueLabelsBatch) dependencies() (*transformedDeps, error) {
	ik, err := keys.ToIssueKey(i.pb.IssueResourceId)
	if err != nil {
		return nil, fmt.Errorf("could not parse issue key: %w", err)
	}
	i.key = ik

	deps := newTransformedDeps()
	deps.int64Deps.Add(ik.RepositoryKey.String())
	deps.strDeps.Add(i.pb.LabelResourceIds...)

	return deps, nil
}

func (i *issueLabelsBatch) load(ctx context.Context, importer client.Importer, resolved resolvedIDsByResource) error {
	var labels []string
	for _, label := range i.pb.LabelResourceIds {
		labels = append(labels, resolved[label].strVal)
	}

	req := &octov1.AddLabelsToIssueRequest{
		RepositoryId: resolved[i.key.RepositoryKey.String()].int64Val,
		IssueNumber:  i.key.Number,
		Labels:       labels,
	}

	if _, err := importer.AddLabelsToIssue(ctx, req); err != nil {
		i.logger.WithError(err).Error("failed to import issue label batch", kvp.Any("request", req))
		return fmt.Errorf("failed to add lables to issue: %w", err)
	}
	return nil
}
