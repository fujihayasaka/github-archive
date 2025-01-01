package ts

import (
	"testing"

	"github.com/stretchr/testify/require"
)

func TestSorted(t *testing.T) {
	a := &Rule{Tags: []RuleTag{{Tag: "b"}, {Tag: "a"}}}
	b := *a
	b.Tags = sorted(b.Tags)
	require.Len(t, b.Tags, 2)
	require.Equal(t, "b", a.Tags[0].Tag)
	require.Equal(t, "a", a.Tags[1].Tag)
	require.Equal(t, "a", b.Tags[0].Tag)
	require.Equal(t, "b", b.Tags[1].Tag)
}
