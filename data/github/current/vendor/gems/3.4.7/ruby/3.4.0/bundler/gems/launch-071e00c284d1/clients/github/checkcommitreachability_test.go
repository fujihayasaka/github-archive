package github

import (
	"context"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func Test_Queries_CheckCommitReachability_Nil(t *testing.T) {
	r := &parsingGQLRunner{
		responses: []string{
			`{
				"data": {
					"repository": {
						"commitIsInBranchOrTag": null
					}
				}
			}`,
		},
	}

	ctx := context.Background()
	res, err := checkCommitReachability(ctx, r, repoID, "abcdefg")
	require.NoError(t, err)
	assert.Nil(t, res)
}

func Test_Queries_CheckCommitReachability_True(t *testing.T) {
	r := &parsingGQLRunner{
		responses: []string{
			`{
				"data": {
					"repository": {
						"commitIsInBranchOrTag": true
					}
				}
			}`,
		},
	}

	ctx := context.Background()
	res, err := checkCommitReachability(ctx, r, repoID, "abcdefg")
	require.NoError(t, err)
	assert.True(t, *res)
}

func Test_Queries_CheckCommitReachabilityWithMergeQueue_Nil(t *testing.T) {
	r := &parsingGQLRunner{
		responses: []string{
			`{
				"data": {
					"repository": {
						"commitIsInBranchOrTag": null,
                                                "commitIsFromMergeQueue": null
					}
				}
			}`,
		},
	}

	ctx := context.Background()
	res, err := checkCommitReachability(ctx, r, repoID, "abcdefg")
	require.NoError(t, err)
	assert.Nil(t, res)
}

func Test_Queries_CheckCommitReachabilityWithMergeQueue_True(t *testing.T) {
	r := &parsingGQLRunner{
		responses: []string{
			`{
				"data": {
					"repository": {
						"commitIsInBranchOrTag": false,
                                                "commitIsFromMergeQueue": true
					}
				}
			}`,
		},
	}

	ctx := context.Background()
	res, err := checkCommitReachability(ctx, r, repoID, "abcdefg")
	require.NoError(t, err)
	assert.True(t, *res)
}

func Test_Queries_CheckCommitReachabilityWithMergeQueue_False(t *testing.T) {
	r := &parsingGQLRunner{
		responses: []string{
			`{
				"data": {
					"repository": {
						"commitIsInBranchOrTag": false,
                                                "commitIsFromMergeQueue": false
					}
				}
			}`,
		},
	}

	ctx := context.Background()
	res, err := checkCommitReachability(ctx, r, repoID, "abcdefg")
	require.NoError(t, err)
	assert.False(t, *res)
}
