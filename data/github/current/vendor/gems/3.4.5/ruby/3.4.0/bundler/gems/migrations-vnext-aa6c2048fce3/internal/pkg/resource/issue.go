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

type issue struct {
	baseHandler
	pb         *v1.Issue
	key        keys.IssueKey
	importedID int64
}

var _ handler = (*issue)(nil)

func newIssue(i *v1.Issue, logger log.Logger) *issue {
	return &issue{
		baseHandler: baseHandler{logger},
		pb:          i,
	}
}

func (i *issue) resourceID() string {
	return i.pb.ResourceId
}

func (i *issue) dependencies() (*transformedDeps, error) {
	k, err := keys.ToIssueKey(i.pb.ResourceId)
	if err != nil {
		return nil, fmt.Errorf("could not parse issue key: %w", err)
	}
	i.key = k

	deps := newTransformedDeps()
	deps.int64Deps.Add(k.RepositoryKey.String())

	deps.strDeps.Add(i.pb.UserResourceId)
	deps.strDeps.Add(i.pb.AttachmentResourceIds...)
	deps.strDeps.Add(i.pb.AssigneesResourceIds...)
	deps.strDeps.Add(k.BaseURL())
	return deps, nil
}

func (i *issue) transform(resolved resolvedIDsByResource) error {
	// transform the body of the issue to replace attachment URLs with the new URLs
	attachmentURLMapping := make(map[string]string)
	for _, attachmentResourceID := range i.pb.AttachmentResourceIds {
		attachmentURLMapping[attachmentResourceID] = resolved[attachmentResourceID].strVal
	}
	rewriteIssueBodyAttachmentURLs(i.pb, attachmentURLMapping)

	// transform the body of the issue to replace the base URL with the new URL
	i.pb.Body = rewriteBaseURL(i.pb.Body, i.key.BaseURL(), resolved[i.key.BaseURL()].strVal)

	return nil
}

func (i *issue) load(ctx context.Context, importer client.Importer, resolved resolvedIDsByResource) error {
	req := &octov1.ImportIssueRequest{
		RepositoryId: resolved[i.key.RepositoryKey.String()].int64Val,
		AuthorLogin:  resolved[i.pb.UserResourceId].strVal,
		Assignees:    valueStrSlice(resolved, i.pb.AssigneesResourceIds),
		Body:         i.pb.Body,
		Title:        i.pb.Title,
		Number:       i.key.Number,
		CreatedAt:    i.pb.CreatedAt,
		ClosedAt:     i.pb.ClosedAt,
		UpdatedAt:    i.pb.UpdatedAt,
	}

	res, err := importer.ImportIssue(ctx, req)
	if err != nil {
		i.logger.WithError(err).Error("failed to import issue", kvp.Any("request", req))
		return fmt.Errorf("failed to load issue: %w", err)
	}
	i.importedID = res.Issue.Id

	return nil
}

func (i *issue) newResolvedIDs() resolvedIDsByResource {
	return resolvedIDsByResource{
		i.resourceID(): &transformedValues{
			int64Val: i.importedID,
		},
	}
}
