package resource

import (
	"context"
	"fmt"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/migrations-vnext/internal/pkg/client"
	"github.com/github/migrations-vnext/internal/pkg/keys"
	octov1 "github.com/github/migrations-vnext/internal/pkg/octoshift/imports/v1"
	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
	"google.golang.org/protobuf/types/known/wrapperspb"
)

type commitComment struct {
	baseHandler
	pb                *v1.CommitComment
	key               keys.CommitCommentKey
	importedCommentID int64
}

var _ handler = (*commitComment)(nil)

func newCommitComment(i *v1.CommitComment, logger log.Logger) *commitComment {
	return &commitComment{
		baseHandler: baseHandler{logger},
		pb:          i,
	}
}

func (i *commitComment) resourceID() string {
	return i.pb.ResourceId
}

func (i *commitComment) dependencies() (*transformedDeps, error) {
	deps := newTransformedDeps()
	k, err := keys.ToCommitCommentKey(i.pb.ResourceId)
	if err != nil {
		return nil, fmt.Errorf("could not parse commit comment key: %w", err)
	}
	i.key = k

	deps.int64Deps.Add(k.RepositoryKey.String())

	deps.strDeps.Add(i.pb.UserResourceId)

	return deps, nil
}

func (i *commitComment) load(ctx context.Context, importer client.Importer, resolved resolvedIDsByResource) error {
	// import commit comment
	req := &octov1.ImportCommitCommentRequest{
		RepositoryId: resolved[i.key.RepositoryKey.String()].int64Val,
		CommitId:     i.key.CommitID,
		AuthorLogin:  resolved[i.pb.UserResourceId].strVal,
		Body:         i.pb.Body,
		Path:         wrapperspb.String(i.pb.Path),
		Position:     wrapperspb.Int64(i.pb.Position),
		CreatedAt:    i.pb.CreatedAt,
	}

	res, err := importer.ImportCommitComment(ctx, req)
	if err != nil {
		return fmt.Errorf("failed to load commit comment: %w", err)
	}
	i.importedCommentID = res.Id

	return nil
}

func (i *commitComment) newResolvedIDs() resolvedIDsByResource {
	return resolvedIDsByResource{
		i.resourceID(): &transformedValues{
			int64Val: i.importedCommentID,
		},
	}
}
