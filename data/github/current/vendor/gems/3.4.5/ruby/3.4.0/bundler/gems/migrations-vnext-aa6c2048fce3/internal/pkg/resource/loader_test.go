package resource

import (
	"testing"

	"github.com/github/migrations-vnext/internal/pkg/dag"
	"github.com/stretchr/testify/assert"
)

func Test_idsToResourceNodes(t *testing.T) {
	has := []string{"a", "b", "c"}
	wants := []dag.Node{
		{ID: "a", Kind: dag.ResourceNode},
		{ID: "b", Kind: dag.ResourceNode},
		{ID: "c", Kind: dag.ResourceNode},
	}

	assert.Equal(t, wants, idsToResourceNodes(has...))
}
