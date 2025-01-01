package resource

import (
	"testing"

	"github.com/github/migrations-vnext/internal/pkg/set"
	"github.com/stretchr/testify/require"
)

func TestTransformedDeps(t *testing.T) {
	t.Run("ignores duplicates", func(t *testing.T) {
		deps := newTransformedDeps()
		deps.int64Deps.Add("a")
		deps.int64Deps.Add("a")
		deps.int64Deps.Add("a")
		require.Len(t, deps.int64Deps.ToSlice(), 1)
	})
	t.Run("can be used as a slice", func(t *testing.T) {
		deps := newTransformedDeps()

		input := []string{"a", "a", "a", "b", "c", "d"}
		expected := []string{"a", "b", "c", "d"}
		deps.int64Deps = set.FromSlice(input)
		require.ElementsMatch(t, expected, deps.int64Deps.ToSlice())
	})
}
