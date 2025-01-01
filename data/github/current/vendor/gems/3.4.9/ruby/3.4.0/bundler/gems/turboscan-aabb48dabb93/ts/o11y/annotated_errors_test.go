package o11y_test

import (
	"testing"

	"github.com/stretchr/testify/require"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/pkg/errors"

	"github.com/github/turboscan/ts/o11y"
)

func TestAnnotatedError(t *testing.T) {
	err := errors.New("test")
	err = o11y.AnnotateError(err, kvp.Int("a", 1), kvp.Int("c", 3))
	err = errors.Wrap(err, "another")
	err = o11y.AnnotateError(err, kvp.Int("b", 2), kvp.Int("c", 4))
	require.ElementsMatch(t, o11y.ErrorToFields(err), []kvp.Field{kvp.Int("a", 1), kvp.Int("b", 2), kvp.Int("c", 3), kvp.Int("c", 4)})
	// When converting to a map, we take the inner-most value of a field.
	require.Equal(t, map[string]any{"a": int64(1), "b": int64(2), "c": int64(3)}, o11y.ErrorToFieldsMap(err))
}
