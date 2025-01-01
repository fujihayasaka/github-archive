package fields_test

import (
	"testing"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/turboghas/internal/fields"
	"github.com/pkg/errors"
	"github.com/stretchr/testify/require"
)

func TestFields(t *testing.T) {
	err := errors.New("test")
	err = fields.Error(err, kvp.Int("a", 1))
	err = errors.Wrap(err, "another")
	err = fields.Error(err, kvp.Int("b", 2))
	require.ElementsMatch(t, fields.From(err), []kvp.Field{kvp.Int("a", 1), kvp.Int("b", 2)})
	require.Equal(t, map[string]any{"a": int64(1), "b": int64(2)}, fields.Map(err))
}
