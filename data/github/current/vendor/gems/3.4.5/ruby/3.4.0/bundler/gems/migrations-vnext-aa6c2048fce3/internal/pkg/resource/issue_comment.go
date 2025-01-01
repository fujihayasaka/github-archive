package resource

import (
	"context"
	"fmt"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/migrations-vnext/internal/pkg/client"
	"github.com/github/migrations-vnext/internal/pkg/keys"
	octov1 "github.com/github/migrations-vnext/internal/pkg/octoshift/imports/v1"
	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
)

type issueComment struct {
	baseHandler
	pb                *v1.IssueComment
	key               keys.IssueCommentKey
	importedCommentID int64
}

var _ handler = (*issueComment)(nil)

func newIssueComment(i *v1.IssueComment, logger log.Logger) *issueComment {
	return &issueComment{
		baseHandler: baseHandler{logger},
		pb:          i,
	}
}

func (i *issueComment) resourceID() string {
	return i.pb.ResourceId
}

func (i *issueComment) dependencies() (*transformedDeps, error) {
	k, err := keys.ToIssueCommentKey(i.pb.ResourceId)
	if err != nil {
		return nil, fmt.Errorf("could not parse issue comment key: %w", err)
	}
	i.key = k

	deps := newTransformedDeps()
	deps.int64Deps.Add(issueIDResource(k))

	deps.strDeps.Add(i.pb.UserResourceId)
	deps.strDeps.Add(i.pb.AttachmentResourceIds...)
	deps.strDeps.Add(k.BaseURL())
	return deps, nil
}

func (i *issueComment) transform(resolved resolvedIDsByResource) error {
	// transform the body of the issue to replace attachment URLs with the new URLs
	attachmentURLMapping := make(map[string]string)
	for _, attachmentResourceID := range i.pb.AttachmentResourceIds {
		attachmentURLMapping[attachmentResourceID] = resolved[attachmentResourceID].strVal
	}
	rewriteIssueCommentBodyAttachmentURLs(i.pb, attachmentURLMapping)

	// transform the body of the issue comment to replace the base URL with the new URL
	i.pb.Body = rewriteBaseURL(i.pb.Body, i.key.BaseURL(), resolved[i.key.BaseURL()].strVal)

	return nil
}

func (i *issueComment) load(ctx context.Context, importer client.Importer, resolved resolvedIDsByResource) error {
	// import issue comment
	req := &octov1.ImportIssueCommentRequest{
		IssueId:     resolved[issueIDResource(i.key)].int64Val,
		AuthorLogin: resolved[i.pb.UserResourceId].strVal,
		Body:        i.pb.Body,
		CreatedAt:   i.pb.CreatedAt,
	}

	res, err := importer.ImportIssueComment(ctx, req)
	if err != nil {
		return fmt.Errorf("failed to load issue comment: %w", err)
	}
	i.importedCommentID = res.IssueComment.Id

	return nil
}

func (i *issueComment) newResolvedIDs() resolvedIDsByResource {
	return resolvedIDsByResource{
		i.resourceID(): &transformedValues{
			int64Val: i.importedCommentID,
		},
	}
}

// issueIDResource returns the resource ID for the issue or pull request that the given issue comment is on.
//
// Pull requests resources store two IDs:
// 1. Pull Request ID
// 2. Issue ID
//
// PR comments work on issue IDs, so this function returns the right key depending
// on whether the issue comment is on a pull request.
//
// Note that this is a bit hacky, and we should probably add support for storing a hash in a resource ID in Redis,
// instead of using separate keys.
func issueIDResource(k keys.IssueCommentKey) string {
	if k.IsPullRequest {
		return k.IssueKey.String() + ":issue_id"
	}
	return k.IssueKey.String()
}
