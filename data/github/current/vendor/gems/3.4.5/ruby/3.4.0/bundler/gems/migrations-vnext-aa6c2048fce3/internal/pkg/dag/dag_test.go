package dag

import (
	"testing"

	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestPrepResource(t *testing.T) {
	t.Run("Constructor disallows empty id", func(t *testing.T) {
		_, err := prepResource("", nil)
		require.Error(t, err)
	})
	t.Run("AddDeps deps can be converted into a slice", func(t *testing.T) {
		res, err := prepResource("id", nil)
		require.NoError(t, err)
		ids := []ID{"a", "b", "c"}
		err = res.AddDeps("a")
		require.NoError(t, err)
		err = res.AddDeps("b", "c")
		require.NoError(t, err)
		require.ElementsMatch(t, ids, res.Deps.ToSlice())
	})
	t.Run("AddDeps disallows empty dep id", func(t *testing.T) {
		res, err := prepResource("id", nil)
		require.NoError(t, err)
		err = res.AddDeps("")
		require.Error(t, err)
		err = res.AddDeps([]string{"a", ""}...)
		require.Error(t, err)
	})
	t.Run("AddDeps ignores duplicates", func(t *testing.T) {
		res, err := prepResource("id", nil)
		require.NoError(t, err)
		err = res.AddDeps("A")
		require.NoError(t, err)
		err = res.AddDeps("A")
		require.NoError(t, err)
		require.Len(t, res.Deps.ToSlice(), 1)
	})
}

// Test_NodeKindIdentity tests the Stringer implementation of NodeKind
// as well as the NodeKindFromString function.
func Test_NodeKindIdentity(t *testing.T) {
	kinds := []NodeKind{EventNode, ResourceNode, UnknownNode}

	for _, kind := range kinds {
		assert.Equal(t, kind, NodeKindFromString(kind.String()))
	}
}

func Test_preparePullRequestReview(t *testing.T) {
	// Test that preparePullRequestReview doesn't add empty deps
	t.Run("shouldn't add empty deps", func(t *testing.T) {
		r := &v1.Resource{
			Resource: &v1.Resource_PullRequestReview{
				PullRequestReview: &v1.PullRequestReview{
					ResourceId:     "http://github.dev/guacamole-bowl/vim/pull/2/files#pullrequestreview-3",
					UserResourceId: "http://github.dev/monalisa",
					Comments: []*v1.PullRequestReviewComment{
						{
							UserResourceId: "http://github.dev/lisamona",
						},
					},
					Threads: []*v1.PullRequestReviewThread{
						{},
					},
				},
			},
		}
		prep, err := preparePullRequestReview(r, r.GetPullRequestReview())
		require.NoError(t, err)
		assert.ElementsMatch(t, []ID{
			"http://github.dev/guacamole-bowl/vim/pull/2",
			"http://github.dev/monalisa",
			"http://github.dev/lisamona",
			"virtual://github.dev/guacamole-bowl/vim/git-data-pushed",
		}, prep.Deps.ToSlice())
	})
}
