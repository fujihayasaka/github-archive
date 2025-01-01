package model

import (
	"fmt"
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestUsesStringer(t *testing.T) {
	cases := []struct {
		uses     fmt.Stringer
		expected string
	}{
		{
			uses:     &UsesDockerImage{Image: "alpine"},
			expected: "docker://alpine",
		},
		{
			uses:     &UsesRepository{Repository: "actions/workflow-parser", Ref: "master"},
			expected: "actions/workflow-parser@master",
		},
		{
			uses:     &UsesRepository{Repository: "actions/workflow-parser", Path: "path", Ref: "master"},
			expected: "actions/workflow-parser/path@master",
		},
		{
			uses:     &UsesPath{Path: "path"},
			expected: "./path",
		},
		{
			uses:     &UsesInvalid{},
			expected: "",
		},
		{
			uses:     &UsesInvalid{Raw: "foo"},
			expected: "foo",
		},
	}

	for _, tc := range cases {
		assert.Equal(t, tc.expected, tc.uses.String())
	}
}

func TestParseActionRef(t *testing.T) {
	callableErr := "reusable workflows should be referenced at the top-level `jobs.*.uses' key, not within steps"
	tests := []struct {
		input       string
		want        Uses
		expectedErr string
	}{
		{input: "./path", want: &UsesPath{Path: "path"}},
		{input: "docker://alpine", want: &UsesDockerImage{Image: "alpine"}},
		{input: "some/repo@main", want: &UsesRepository{Repository: "some/repo", Ref: "main"}},
		{input: "some/repo/path@main", want: &UsesRepository{Repository: "some/repo", Ref: "main", Path: "path"}},
		{input: "some/repo/.github/workflows/path.yml@main", expectedErr: callableErr},
	}
	for _, tc := range tests {
		actual, err := ParseActionRef(tc.input)

		if tc.expectedErr == "" {
			assert.Nil(t, err, "no error expected")
			assert.Equal(t, tc.want, actual)
		} else {
			assert.NotNil(t, err, "expected non-nil error")
			assert.Equal(t, tc.expectedErr, err.Error())
		}
	}
}
