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

type pullRequest struct {
	baseHandler
	pb              *v1.PullRequest
	key             keys.PullRequestKey
	importedPrID    int64
	importedIssueID int64
}

var _ handler = (*pullRequest)(nil)

func newPullRequest(pb *v1.PullRequest, logger log.Logger) *pullRequest {
	return &pullRequest{
		baseHandler: baseHandler{logger},
		pb:          pb,
	}
}

func (p *pullRequest) resourceID() string {
	return p.pb.ResourceId
}

func (p *pullRequest) dependencies() (*transformedDeps, error) {
	k, err := keys.ToPullRequestKey(p.pb.ResourceId)
	if err != nil {
		return nil, fmt.Errorf("could not parse pr key: %w", err)
	}
	p.key = k

	deps := newTransformedDeps()
	deps.int64Deps.Add(k.RepositoryKey.String())

	deps.strDeps.Add(p.pb.UserResourceId)
	deps.strDeps.Add(p.pb.AssigneesResourceIds...)
	deps.strDeps.Add(p.pb.ReviewersResourceIds...)
	deps.strDeps.Add(p.pb.AttachmentResourceIds...)
	deps.strDeps.Add(k.BaseURL())
	return deps, nil
}

func (p *pullRequest) transform(resolved resolvedIDsByResource) error {
	// transform the body of the pr to replace attachment URLs with the new URLs
	urlMap := make(map[string]string)
	for _, id := range p.pb.AttachmentResourceIds {
		urlMap[id] = resolved[id].strVal
	}
	rewritePullRequestBodyAttachmentURLs(p.pb, urlMap)

	// transform the body of the pr to replace the base URL with the new URL
	p.pb.Body = rewriteBaseURL(p.pb.Body, p.key.BaseURL(), resolved[p.key.BaseURL()].strVal)

	return nil
}

func (p *pullRequest) load(ctx context.Context, importer client.Importer, resolved resolvedIDsByResource) error {
	// import pr
	req := &octov1.ImportPullRequestRequest{
		RepositoryId:     resolved[p.key.RepositoryKey.String()].int64Val,
		AuthorLogin:      resolved[p.pb.UserResourceId].strVal,
		Assignees:        valueStrSlice(resolved, p.pb.AssigneesResourceIds),
		Reviewers:        valueStrSlice(resolved, p.pb.ReviewersResourceIds),
		Body:             p.pb.Body,
		Title:            p.pb.Title,
		Number:           p.key.Number,
		IsDraft:          p.pb.IsDraft,
		CreatedAt:        p.pb.CreatedAt,
		ClosedAt:         p.pb.ClosedAt,
		MergedAt:         p.pb.MergedAt,
		BaseRefName:      p.pb.BaseRef.Name,
		HeadRefName:      p.pb.HeadRef.Name,
		BaseRefCommitSha: p.pb.BaseRef.CommitSha,
		HeadRefCommitSha: p.pb.HeadRef.CommitSha,
		MergeCommitSha:   p.pb.MergeCommitSha,
	}

	res, err := importer.ImportPullRequest(ctx, req)
	if err != nil {
		p.logger.WithError(err).Error("failed to import pr", kvp.Any("request", req))
		return fmt.Errorf("failed to load pr: %w", err)
	}
	p.importedPrID = res.PullRequest.Id
	p.importedIssueID = res.PullRequest.IssueId

	return nil
}

func (p *pullRequest) newResolvedIDs() resolvedIDsByResource {
	return resolvedIDsByResource{
		p.resourceID(): &transformedValues{
			int64Val: p.importedPrID,
		},
		p.resourceID() + ":issue_id": &transformedValues{
			int64Val: p.importedIssueID,
		},
	}
}
