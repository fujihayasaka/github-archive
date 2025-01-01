package types

import (
	"fmt"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestIsHeadRef(t *testing.T) {
	cases := []struct {
		Ref      GitRef
		Expected bool
	}{
		{GitRefZeroValue, false},
		{DefaultBranch, false},
		{GitRef("master"), false},
		{NewBranchRef("master"), true},
		{NewTagRef("v1.0"), false},
	}

	for _, tc := range cases {
		t.Run(tc.Ref.String(), func(tt *testing.T) {
			require.Equal(tt, tc.Ref.IsHeadRef(), tc.Expected)
		})
	}
}

func TestIsTagRef(t *testing.T) {
	cases := []struct {
		Ref      GitRef
		Expected bool
	}{
		{GitRefZeroValue, false},
		{DefaultBranch, false},
		{GitRef("master"), false},
		{NewBranchRef("master"), false},
		{NewTagRef("v1.0"), true},
	}

	for _, tc := range cases {
		t.Run(tc.Ref.String(), func(tt *testing.T) {
			require.Equal(tt, tc.Ref.IsTagRef(), tc.Expected)
		})
	}
}

func TestIsZeroValue(t *testing.T) {
	cases := []struct {
		Ref      GitRef
		Expected bool
	}{
		{GitRefZeroValue, true},
		{DefaultBranch, false},
		{GitRef("master"), false},
		{NewBranchRef("master"), false},
		{NewTagRef("v1.0"), false},
	}

	for _, tc := range cases {
		t.Run(tc.Ref.String(), func(tt *testing.T) {
			require.Equal(tt, tc.Ref.IsZeroValue(), tc.Expected)
		})
	}
}

func ExampleGitRef_TagOrHeadName_forBranchesOrTags() {
	fmt.Println(GitRef("refs/heads/master").TagOrHeadName())
	fmt.Println(GitRef("refs/tags/v1.0.1").TagOrHeadName())
	fmt.Println(GitRef("refs/heads/yashtestingbranchtree/1").TagOrHeadName())
	fmt.Println(GitRef("refs/heads/this/is/quite/a/long/name").TagOrHeadName())
	fmt.Println(GitRef("refs/tags/tags/have/slashes/too").TagOrHeadName())
	// Output:
	// master
	// v1.0.1
	// yashtestingbranchtree/1
	// this/is/quite/a/long/name
	// tags/have/slashes/too
}

func TestGitRef_TagOrHeadName_nonTagOrHeads(t *testing.T) {
	egs := []string{
		"",
		"invalid",
		"refs/",
		"refs/prs/11/head",
		"refs/my-ref",
	}
	for _, eg := range egs {
		t.Run(eg, func(t *testing.T) {
			assert.Equal(t, "", GitRef(eg).TagOrHeadName())
		})
	}
}

func TestGitRef_TrimRefPrefix(t *testing.T) {
	egs := []struct {
		Ref      string
		Expected string
	}{
		{"", ""},
		{"refs/heads/master", "master"},
		{"refs/tags/v1.0.1", "v1.0.1"},
		{"refs/heads/yashtestingbranchtree/1", "yashtestingbranchtree/1"},
		{"refs/tags/tags/have/slashes/too", "tags/have/slashes/too"},
		{"refs/pull/1234/merge", "1234/merge"},
		{"something", "something"},
		{"refs/my-ref", "refs/my-ref"},
	}
	for _, eg := range egs {
		t.Run(eg.Ref, func(t *testing.T) {
			assert.Equal(t, eg.Expected, GitRef(eg.Ref).TrimRefPrefix())
		})
	}
}
