package observability

import (
	"testing"

	"github.com/stretchr/testify/require"

	"github.com/github/go-kvp"

	"github.com/github/launch/observability/statter"
)

func TestCombineFieldsTags(t *testing.T) {
	t.Run("Test populated args", func(tt *testing.T) {
		fields := []kvp.Field{
			kvp.Any("foo", 1),
			kvp.Int("bar", 2),
		}

		tags := statter.Tags{
			"baz": "three",
			"qaz": "four",
		}

		allFields := combineFieldsTags("my.key", fields, tags)
		require.Len(tt, allFields, 5)
	})

	t.Run("Test nil args", func(tt *testing.T) {
		var fields []kvp.Field
		var tags statter.Tags

		allFields := combineFieldsTags("my.key", fields, tags)
		require.Len(tt, allFields, 1)
	})
}
