package github

import (
	"context"

	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/trace"

	"github.com/github/launch/observability/tracing"
	"github.com/github/launch/types"
)

type FilterDiffResult struct {
	Paths    []string `json:"paths"`
	Advisory string   `json:"advisory"`
}

func (c *client) GetFilterDiff(ctx context.Context, repoGID types.GlobalID, headBase types.BeforeAfterSHA, ref types.GitRef, pullIDMaybe types.GlobalID) (*FilterDiffResult, error) {
	ctx, span := tracing.Start(ctx, trace.WithAttributes(
		attribute.String("gh.repo.global_id", string(repoGID)),
	))
	defer span.End()

	return getFilterDiff(ctx, c, repoGID, headBase, ref, pullIDMaybe)
}

func getFilterDiff(ctx context.Context, c gqlRunner, repoGID types.GlobalID, headBase types.BeforeAfterSHA, ref types.GitRef, pullIDMaybe types.GlobalID) (*FilterDiffResult, error) {
	const gql = `
			query GetFilterDiff($repo: ID!, $head: GitObjectID!, $base: GitObjectID!, $pull: ID, $ref: String) {
				repository: node(id: $repo) {
					... on Repository {
						actionsFilterDiff(headSha: $head, baseSha: $base, pullRequest: $pull, ref: $ref) {
							paths
							advisory
						}
					}
				}
			}`
	var resp struct {
		Repository struct {
			ActionsFilterDiff FilterDiffResult
		}
	}
	vars := map[string]any{
		"repo": repoGID,
		"head": headBase.After,
		"base": headBase.Before,
		"ref":  ref,
	}
	if pullIDMaybe != "" {
		vars["pull"] = pullIDMaybe
	}
	_, err := c.do(ctx, "GetFilterDiff", "query", gql, vars, &resp, nil)
	if err != nil {
		return nil, err
	}
	return &resp.Repository.ActionsFilterDiff, nil
}
