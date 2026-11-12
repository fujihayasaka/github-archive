package types

import (
	"testing"

	"github.com/stretchr/testify/require"
)

func TestNewPattern(t *testing.T) {
	pattern := []byte("[a-zA-Z_]+")
	p := NewPattern(pattern)
	require.Equal(t, &Pattern{Pattern: pattern}, p)
}

func TestPatternValidate(t *testing.T) {
	var p *Pattern
	require.NoError(t, p.Validate())

	p = &Pattern{}
	require.EqualError(t, p.Validate(), "twirp error invalid_argument: pattern.pattern is required")

	p = &Pattern{Pattern: []byte("")}
	require.EqualError(t, p.Validate(), "twirp error invalid_argument: pattern.pattern is required")

	p = NewPattern([]byte("[a-zA-Z_]+"))
	require.NoError(t, p.Validate())
}
