package github

import (
	"context"

	"github.com/github/launch/observability/tracing"
	"github.com/github/launch/types"
)

func (c *client) CheckCommitReachability(ctx context.Context, repoGID types.GlobalID, commitOid types.CommitSha) (*bool, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()
	return checkCommitReachability(ctx, c, repoGID, commitOid)
}

func checkCommitReachability(ctx context.Context, c gqlRunner, repoGID types.GlobalID, commitOid types.CommitSha) (*bool, error) {
	const gql = `
		query CheckCommitReachability($repo: ID!, $oid: GitObjectID!) {
			repository: node(id: $repo) {
				... on Repository {
					commitIsInBranchOrTag(oid: $oid)
					commitIsFromMergeQueue(oid: $oid)
				}
			}
		}
	`

	var resp struct {
		Repository struct {
			CommitIsInBranchOrTag  *bool
			CommitIsFromMergeQueue *bool
		}
	}

	vars := map[string]any{
		"repo": repoGID.String(),
		"oid":  commitOid.String(),
	}

	if _, err := c.do(ctx, "CheckCommitReachability", "query", gql, vars, &resp, nil); err != nil {
		return nil, err
	}

	if resp.Repository.CommitIsInBranchOrTag == nil && resp.Repository.CommitIsFromMergeQueue == nil {
		return nil, nil
	}

	reachability := checkBoolPointerTrue(resp.Repository.CommitIsInBranchOrTag) || checkBoolPointerTrue(resp.Repository.CommitIsFromMergeQueue)

	return &reachability, nil
}

func checkBoolPointerTrue(boolPtr *bool) bool {
	if boolPtr == nil {
		return false
	}

	return *boolPtr
}
