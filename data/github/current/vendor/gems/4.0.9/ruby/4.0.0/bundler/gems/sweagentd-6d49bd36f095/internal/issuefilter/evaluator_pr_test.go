package issuefilter

import (
	"testing"

	gg "github.com/google/go-github/v75/github"
	"github.com/stretchr/testify/assert"
)

func prWithLabels(names ...string) *gg.PullRequest {
	labels := make([]*gg.Label, len(names))
	for i, n := range names {
		labels[i] = &gg.Label{Name: ptr(n)}
	}
	return &gg.PullRequest{Labels: labels}
}

func prWithDraft(draft bool) *gg.PullRequest {
	return &gg.PullRequest{Draft: ptr(draft)}
}

func prWithBranches(base, head string) *gg.PullRequest {
	return &gg.PullRequest{
		Base: &gg.PullRequestBranch{Ref: ptr(base)},
		Head: &gg.PullRequestBranch{Ref: ptr(head)},
	}
}

func barePR() *gg.PullRequest {
	return &gg.PullRequest{}
}

// === Blank / nil queries ===

func TestEvaluatePR_BlankQuery(t *testing.T) {
	result := EvaluatePR("", barePR())
	assert.True(t, result.Matched)
	assert.Empty(t, result.Error)
}

func TestEvaluatePR_NilPR(t *testing.T) {
	result := EvaluatePR("label:bug", nil)
	assert.True(t, result.Matched)
	assert.Contains(t, result.Error, "nil pull request")
}

// === Shared qualifiers (label / author / assignee) ===

func TestEvaluatePR_LabelMatch(t *testing.T) {
	pr := prWithLabels("bug", "needs-review")

	assert.True(t, EvaluatePR("label:bug", pr).Matched)
	assert.True(t, EvaluatePR("label:bug,needs-review", pr).Matched)
	assert.False(t, EvaluatePR("label:enhancement", pr).Matched)
	assert.False(t, EvaluatePR("label:bug,unknown", pr).Matched)
}

func TestEvaluatePR_AuthorMatch(t *testing.T) {
	pr := &gg.PullRequest{User: &gg.User{Login: ptr("octocat")}}

	assert.True(t, EvaluatePR("author:octocat", pr).Matched)
	assert.True(t, EvaluatePR("author:@octocat", pr).Matched)
	assert.False(t, EvaluatePR("author:hubot", pr).Matched)
}

// === PR-only qualifiers ===

func TestEvaluatePR_DraftTrue(t *testing.T) {
	assert.True(t, EvaluatePR("draft:true", prWithDraft(true)).Matched)
	assert.False(t, EvaluatePR("draft:true", prWithDraft(false)).Matched)
	// PR.Draft nil → not draft.
	assert.False(t, EvaluatePR("draft:true", barePR()).Matched)
}

func TestEvaluatePR_DraftFalse(t *testing.T) {
	assert.False(t, EvaluatePR("draft:false", prWithDraft(true)).Matched)
	assert.True(t, EvaluatePR("draft:false", prWithDraft(false)).Matched)
	assert.True(t, EvaluatePR("draft:false", barePR()).Matched)
}

func TestEvaluatePR_DraftInvalidValueFailsOpen(t *testing.T) {
	result := EvaluatePR("draft:maybe", prWithDraft(true))
	assert.True(t, result.Matched)
	assert.Contains(t, result.Error, "unsupported draft:maybe value")
}

func TestEvaluatePR_DraftOnIssueFailsOpenWithWarning(t *testing.T) {
	// Same query applied via Evaluate (issue path) must fail-open with a warning.
	result := Evaluate("draft:true", &gg.Issue{})
	assert.True(t, result.Matched)
	assert.Contains(t, result.Error, "draft: qualifier is only supported on pull requests")
}

func TestEvaluatePR_BaseAndHeadMatch(t *testing.T) {
	pr := prWithBranches("main", "feature/login")

	assert.True(t, EvaluatePR("base:main", pr).Matched)
	assert.True(t, EvaluatePR("head:feature/login", pr).Matched)
	assert.False(t, EvaluatePR("base:develop", pr).Matched)
	assert.False(t, EvaluatePR("head:other", pr).Matched)

	// Combined query (implicit AND).
	assert.True(t, EvaluatePR("base:main head:feature/login", pr).Matched)
	assert.False(t, EvaluatePR("base:main head:other", pr).Matched)
}

func TestEvaluatePR_BaseHeadOnIssueFailsOpen(t *testing.T) {
	r := Evaluate("base:main", &gg.Issue{})
	assert.True(t, r.Matched)
	assert.Contains(t, r.Error, "base: qualifier is only supported on pull requests")
}

// === is: / type: cross-target behaviour ===

func TestEvaluatePR_IsPRTrueIsIssueFalse(t *testing.T) {
	pr := barePR()
	assert.True(t, EvaluatePR("is:pr", pr).Matched)
	assert.False(t, EvaluatePR("is:issue", pr).Matched)
}

func TestEvaluatePR_TypePRTrueTypeIssueFalse(t *testing.T) {
	pr := barePR()
	assert.True(t, EvaluatePR("type:pr", pr).Matched)
	assert.False(t, EvaluatePR("type:issue", pr).Matched)
}

func TestEvaluatePR_IsDraft(t *testing.T) {
	assert.True(t, EvaluatePR("is:draft", prWithDraft(true)).Matched)
	assert.False(t, EvaluatePR("is:draft", prWithDraft(false)).Matched)
}

// === Issue evaluator's existing is:pr semantics still rejected ===

func TestEvaluate_IsPRStillRejectsIssues(t *testing.T) {
	// Regression check: the issue evaluator must continue to reject is:pr.
	result := Evaluate("is:pr", &gg.Issue{})
	assert.False(t, result.Matched)
}

// === Negation works on PR qualifiers ===

func TestEvaluatePR_NegatedDraft(t *testing.T) {
	assert.False(t, EvaluatePR("-draft:true", prWithDraft(true)).Matched)
	assert.True(t, EvaluatePR("-draft:true", prWithDraft(false)).Matched)
}

func TestEvaluatePR_LabelAndNotDraft(t *testing.T) {
	pr := &gg.PullRequest{
		Labels: []*gg.Label{{Name: ptr("dependencies")}},
		Draft:  ptr(false),
	}
	assert.True(t, EvaluatePR("label:dependencies -draft:true", pr).Matched)
}
