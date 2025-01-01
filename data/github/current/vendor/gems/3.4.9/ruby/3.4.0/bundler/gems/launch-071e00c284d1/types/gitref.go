package types

import (
	"regexp"
	"strings"
)

const branchRef = "refs/heads/"
const pullRef = "refs/pull/"
const tagRef = "refs/tags/"

var pullHeadPattern = regexp.MustCompile(`^refs/pull/[0-9]+/head$`)

// DefaultBranch represents the default branch of a repository.
const DefaultBranch = GitRef("HEAD")

// GitRefZeroValue represents the absence of a ref.
const GitRefZeroValue = GitRef("")

// NewBranchRef creates a GitRef pointing to the head of a branch
func NewBranchRef(branch string) GitRef {
	return GitRef(branchRef + branch)
}

// NewTagRef creates a GitRef pointing to the head of a branch
func NewTagRef(branch string) GitRef {
	return GitRef(tagRef + branch)
}

// GitRef represents a symbolic name of a Git commit.
type GitRef string

func (GitRef) isCommitish() {}

// String returns the string form of this.
func (g GitRef) String() string {
	return string(g)
}

// IsHeadRef returns true if the reference is to a branch ref
func (g GitRef) IsHeadRef() bool {
	return strings.HasPrefix(string(g), branchRef)
}

// IsTagRef returns true if the reference is to a tag ref
func (g GitRef) IsTagRef() bool {
	return strings.HasPrefix(string(g), tagRef)
}

// IsPullHeadRef returns true if the reference is to a ref like `refs/pull/1/head`
func (g GitRef) IsPullHeadRef() bool {
	return pullHeadPattern.MatchString(string(g))
}

// IsZeroValue returns true if this is IsZeroValue.
func (g GitRef) IsZeroValue() bool {
	return g == GitRefZeroValue
}

// TagOrHeadName returns the branch or tag name, or "" for any non-tag/branch name
func (g GitRef) TagOrHeadName() string {
	s := g.String()
	if strings.HasPrefix(s, branchRef) {
		return strings.TrimPrefix(s, branchRef)
	}
	if strings.HasPrefix(s, tagRef) {
		return strings.TrimPrefix(s, tagRef)
	}
	return ""
}

func (g GitRef) TrimRefPrefix() string {
	s := g.String()
	if strings.HasPrefix(s, branchRef) {
		return strings.TrimPrefix(s, branchRef)
	}
	if strings.HasPrefix(s, tagRef) {
		return strings.TrimPrefix(s, tagRef)
	}
	if strings.HasPrefix(s, pullRef) {
		return strings.TrimPrefix(s, pullRef)
	}
	return s
}
