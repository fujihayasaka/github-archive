package github

import (
	"context"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/github/launch/types"
	terrors "github.com/github/launch/types/errors"
)

const (
	repoID = types.GlobalID("repo-id-a")
)

var (
	ref = types.GitRef("refs/heads/master")
)

func Test_Queries_RunFilters_Outgoing(t *testing.T) {
	r := &recordingAndValidatingGQLRunner{schema: loadSchema(t)}

	ctx := context.Background()
	_, err := getFilterDiff(ctx, r, repoID, types.BeforeAfterSHA{
		Before: "aabb",
		After:  "ccdd",
	}, ref, "")
	require.EqualError(t, err, RecordingGQLRunnerNoResponse)

	assert.Equal(t, map[string]any{
		"head": types.CommitSha("ccdd"),
		"base": types.CommitSha("aabb"),
		"repo": repoID,
		"ref":  ref,
	}, r.queries[0].Variables)
}

func Test_Queries_RunFilters_ResultParsing(t *testing.T) {
	r := parsingGQLRunner{
		responses: []string{
			`{
				"data": {
					"repository": {
						"actionsFilterDiff": {
							"paths": ["one", "two"]
						}
					}
				}
			}`,
			`{
				"data": {
					"repository": {
						"actionsFilterDiff": {
							"advisory": "empty"
						}
					}
				}
			}`,
			`{
				"data": {
					"repository": {
						"actionsFilterDiff": null
					}
				},
				"errors": [
					{
					  "type": "NOT_FOUND",
					  "path": [
						"repository",
						"actionsFilterDiff"
					  ],
					  "message": "Could not find referenced commits"
					}
				]
			}`,
		},
	}

	ctx := context.Background()

	res, err := getFilterDiff(ctx, &r, repoID, types.BeforeAfterSHA{
		Before: "aabb",
		After:  "ccdd",
	}, ref, "")
	require.NoError(t, err)
	require.NotNil(t, res)
	assert.Equal(t, &FilterDiffResult{
		Paths:    []string{"one", "two"},
		Advisory: "",
	}, res)

	res, err = getFilterDiff(ctx, &r, repoID, types.BeforeAfterSHA{
		Before: "aabb",
		After:  "ccdd",
	}, ref, "")
	require.NoError(t, err)
	require.NotNil(t, res)
	assert.Equal(t, &FilterDiffResult{
		Advisory: "empty",
	}, res)

	res, err = getFilterDiff(ctx, &r, repoID, types.BeforeAfterSHA{
		Before: "aabb",
		After:  "ccdd",
	}, ref, "")
	require.Error(t, err)
	require.Nil(t, res)
	assert.True(t, terrors.IsNotFoundError(err))
	assert.True(t, terrors.IsRetryable(err))
}
