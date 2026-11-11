package types

import (
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestNewPathspec(t *testing.T) {
	p := NewPathspec(NewPathspecItem(
		PathspecItem_PATTERN_TYPE_WILDCARD,
		NewPattern([]byte("docs/*.md")),
	))
	require.Equal(t, &Pathspec{Items: []*PathspecItem{
		{
			Patterns:    []*Pattern{&Pattern{Pattern: []byte("docs/*.md")}},
			PatternType: PathspecItem_PATTERN_TYPE_WILDCARD,
		},
	}}, p)
}

func TestPathspecValidateErrors(t *testing.T) {
	var tests = []struct {
		name string
		p    *Pathspec
		err  string
	}{
		{
			"invalid pattern type",
			&Pathspec{Items: []*PathspecItem{{Patterns: []*Pattern{NewPattern([]byte("src/*"))}}}},
			"twirp error invalid_argument: pattern_type must be one of: literal, glob, wildcard",
		},
		{
			"empty pathspec pattern",
			&Pathspec{Items: []*PathspecItem{{PatternType: PathspecItem_PATTERN_TYPE_WILDCARD, Patterns: []*Pattern{nil, &Pattern{Pattern: []byte("")}}}}},
			"twirp error invalid_argument: patterns[0] is required",
		},
		{
			"pathspec pattern starting with colon",
			&Pathspec{Items: []*PathspecItem{{PatternType: PathspecItem_PATTERN_TYPE_WILDCARD, Patterns: []*Pattern{&Pattern{Pattern: []byte(":")}}}}},
			"twirp error invalid_argument: patterns[0] cannot start with a colon",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := tt.p.Validate()
			require.Error(t, err)
			assert.Equal(t, tt.err, err.Error())

		})
	}
}

func TestPathspecValidate(t *testing.T) {
	var p *Pathspec
	require.NoError(t, p.Validate())

	p = NewPathspec(NewPathspecItem(PathspecItem_PATTERN_TYPE_WILDCARD, NewPattern([]byte("docs/*.md"))))
	require.NoError(t, p.Validate())
}
