package issuefilter

import (
	"testing"

	gg "github.com/google/go-github/v75/github"
	"github.com/stretchr/testify/assert"
)

func ptr[T any](v T) *T { return &v }

func issueWithLabels(names ...string) *gg.Issue {
	labels := make([]*gg.Label, len(names))
	for i, n := range names {
		labels[i] = &gg.Label{Name: ptr(n)}
	}
	return &gg.Issue{Labels: labels}
}

func issueWithAssignees(logins ...string) *gg.Issue {
	users := make([]*gg.User, len(logins))
	for i, l := range logins {
		users[i] = &gg.User{Login: ptr(l)}
	}
	return &gg.Issue{Assignees: users}
}

func issueWithAuthor(login string) *gg.Issue {
	return &gg.Issue{User: &gg.User{Login: ptr(login)}}
}

func issueWithMilestone(title string) *gg.Issue {
	return &gg.Issue{Milestone: &gg.Milestone{Title: ptr(title)}}
}

func issueWithType(name string) *gg.Issue {
	return &gg.Issue{Type: &gg.IssueType{Name: ptr(name)}}
}

func bareIssue() *gg.Issue {
	return &gg.Issue{}
}

// === Blank / nil queries ===

func TestEvaluate_BlankQuery(t *testing.T) {
	result := Evaluate("", bareIssue())
	assert.True(t, result.Matched)
	assert.Empty(t, result.Error)
}

func TestEvaluate_WhitespaceQuery(t *testing.T) {
	result := Evaluate("   ", bareIssue())
	assert.True(t, result.Matched)
	assert.Empty(t, result.Error)
}

// === label:<name> ===

func TestEvaluate_MatchesLabelPresent(t *testing.T) {
	issue := issueWithLabels("skip-triage")
	result := Evaluate("label:skip-triage", issue)
	assert.True(t, result.Matched)
	assert.Empty(t, result.Error)
}

func TestEvaluate_NoMatchLabelAbsent(t *testing.T) {
	result := Evaluate("label:skip-triage", bareIssue())
	assert.False(t, result.Matched)
	assert.Empty(t, result.Error)
}

func TestEvaluate_LabelCaseInsensitive(t *testing.T) {
	issue := issueWithLabels("Bug")
	result := Evaluate("label:bug", issue)
	assert.True(t, result.Matched)
}

func TestEvaluate_LabelQuotedWithSpaces(t *testing.T) {
	issue := issueWithLabels("good first issue")
	result := Evaluate(`label:"good first issue"`, issue)
	assert.True(t, result.Matched)
}

// === assignee:<login> ===

func TestEvaluate_MatchesAssignee(t *testing.T) {
	issue := issueWithAssignees("octocat")
	result := Evaluate("assignee:octocat", issue)
	assert.True(t, result.Matched)
}

func TestEvaluate_NoMatchAssigneeWrong(t *testing.T) {
	issue := issueWithAssignees("octocat")
	result := Evaluate("assignee:nonexistent", issue)
	assert.False(t, result.Matched)
}

func TestEvaluate_AssigneeWithAtPrefix(t *testing.T) {
	issue := issueWithAssignees("octocat")
	result := Evaluate("assignee:@octocat", issue)
	assert.True(t, result.Matched)
}

func TestEvaluate_AssigneeCaseInsensitive(t *testing.T) {
	issue := issueWithAssignees("octocat")
	result := Evaluate("assignee:OCTOCAT", issue)
	assert.True(t, result.Matched)
}

// === has:<field> ===

func TestEvaluate_HasLabelWhenPresent(t *testing.T) {
	issue := issueWithLabels("enhancement")
	result := Evaluate("has:label", issue)
	assert.True(t, result.Matched)
}

func TestEvaluate_HasLabelWhenAbsent(t *testing.T) {
	result := Evaluate("has:label", bareIssue())
	assert.False(t, result.Matched)
}

func TestEvaluate_HasAssigneeWhenPresent(t *testing.T) {
	issue := issueWithAssignees("octocat")
	result := Evaluate("has:assignee", issue)
	assert.True(t, result.Matched)
}

func TestEvaluate_HasAssigneeWhenAbsent(t *testing.T) {
	result := Evaluate("has:assignee", bareIssue())
	assert.False(t, result.Matched)
}

// === no:<field> ===

func TestEvaluate_NoLabelWhenAbsent(t *testing.T) {
	result := Evaluate("no:label", bareIssue())
	assert.True(t, result.Matched)
}

func TestEvaluate_NoLabelWhenPresent(t *testing.T) {
	issue := issueWithLabels("bug")
	result := Evaluate("no:label", issue)
	assert.False(t, result.Matched)
}

func TestEvaluate_NoAssigneeWhenAbsent(t *testing.T) {
	result := Evaluate("no:assignee", bareIssue())
	assert.True(t, result.Matched)
}

func TestEvaluate_NoAssigneeWhenPresent(t *testing.T) {
	issue := issueWithAssignees("octocat")
	result := Evaluate("no:assignee", issue)
	assert.False(t, result.Matched)
}

// === Boolean operators ===

func TestEvaluate_ORMatchesWhenOneSideTrue(t *testing.T) {
	issue := issueWithLabels("skip-triage")
	result := Evaluate("label:skip-triage OR has:assignee", issue)
	assert.True(t, result.Matched)
}

func TestEvaluate_ORNoMatchWhenBothFalse(t *testing.T) {
	result := Evaluate("label:skip-triage OR has:assignee", bareIssue())
	assert.False(t, result.Matched)
}

func TestEvaluate_ANDMatchesBothTrue(t *testing.T) {
	issue := &gg.Issue{
		Labels:    []*gg.Label{{Name: ptr("bug")}},
		Assignees: []*gg.User{{Login: ptr("octocat")}},
	}
	result := Evaluate("label:bug AND has:assignee", issue)
	assert.True(t, result.Matched)
}

func TestEvaluate_ANDFailsWhenOneFalse(t *testing.T) {
	issue := issueWithLabels("bug")
	result := Evaluate("label:bug AND has:assignee", issue)
	assert.False(t, result.Matched)
}

func TestEvaluate_ImplicitAND(t *testing.T) {
	issue := &gg.Issue{
		Labels:    []*gg.Label{{Name: ptr("bug")}},
		Assignees: []*gg.User{{Login: ptr("octocat")}},
	}
	result := Evaluate("label:bug has:assignee", issue)
	assert.True(t, result.Matched)
}

// === Negation ===

func TestEvaluate_NegatedLabelNoMatch(t *testing.T) {
	result := Evaluate("-label:skip-triage", bareIssue())
	assert.True(t, result.Matched)
}

func TestEvaluate_NegatedLabelPresent(t *testing.T) {
	issue := issueWithLabels("skip-triage")
	result := Evaluate("-label:skip-triage", issue)
	assert.False(t, result.Matched)
}

func TestEvaluate_NegatedHasLabel(t *testing.T) {
	result := Evaluate("-has:label", bareIssue())
	assert.True(t, result.Matched)
}

func TestEvaluate_NegatedHasLabelWhenPresent(t *testing.T) {
	issue := issueWithLabels("bug")
	result := Evaluate("-has:label", issue)
	assert.False(t, result.Matched)
}

func TestEvaluate_MixedNegationWithOR(t *testing.T) {
	issue := issueWithAssignees("octocat")
	result := Evaluate("-label:bug OR has:assignee", issue)
	assert.True(t, result.Matched)
}

// === Parentheses / complex queries ===

func TestEvaluate_ParenthesizedORAndAND(t *testing.T) {
	issue := issueWithLabels("bug")
	result := Evaluate("(label:bug OR label:feature) AND no:assignee", issue)
	assert.True(t, result.Matched)
}

func TestEvaluate_ParenthesizedNoMatch(t *testing.T) {
	issue := issueWithLabels("docs")
	result := Evaluate("(label:bug OR label:feature) AND no:assignee", issue)
	assert.False(t, result.Matched)
}

func TestEvaluate_MultipleLabelsBothPresent(t *testing.T) {
	issue := issueWithLabels("bug", "enhancement")
	result := Evaluate("label:bug label:enhancement", issue)
	assert.True(t, result.Matched)
}

func TestEvaluate_MultipleLabelsOnlyOnePresent(t *testing.T) {
	issue := issueWithLabels("bug")
	result := Evaluate("label:bug label:enhancement", issue)
	assert.False(t, result.Matched)
}

// === Free-text ===

func TestEvaluate_FreeTextMatchesFailOpen(t *testing.T) {
	result := Evaluate("hello world", bareIssue())
	assert.True(t, result.Matched)
	assert.Empty(t, result.Error)
}

// === Unknown qualifiers ===

func TestEvaluate_UnknownQualifierFailOpen(t *testing.T) {
	result := Evaluate("unknown:value", bareIssue())
	assert.True(t, result.Matched)
	assert.NotEmpty(t, result.Error, "unknown qualifiers should produce a warning per RFC fail-open spec")
	assert.Contains(t, result.Error, "unsupported qualifier")
}

func TestEvaluate_UnknownHasFieldFailOpen(t *testing.T) {
	result := Evaluate("has:reaction", bareIssue())
	assert.True(t, result.Matched)
	assert.NotEmpty(t, result.Error, "unknown has: fields should produce a warning")
	assert.Contains(t, result.Error, "unsupported has:reaction")
}

func TestEvaluate_UnknownNoFieldFailOpen(t *testing.T) {
	result := Evaluate("no:reaction", bareIssue())
	assert.True(t, result.Matched)
	assert.NotEmpty(t, result.Error, "unknown no: fields should produce a warning")
	assert.Contains(t, result.Error, "unsupported no:reaction")
}

// === Invalid syntax ===

func TestEvaluate_InvalidSyntaxFailOpen(t *testing.T) {
	result := Evaluate("((((", bareIssue())
	assert.True(t, result.Matched)
	assert.NotEmpty(t, result.Error)
}

// === Negated unknown qualifiers still fail-open ===

func TestEvaluate_NegatedUnknownQualifierFailOpen(t *testing.T) {
	result := Evaluate("-unknown:value", bareIssue())
	assert.True(t, result.Matched, "negated unknown qualifier should fail-open")
	assert.NotEmpty(t, result.Error)
	assert.Contains(t, result.Error, "unsupported qualifier")
}

func TestEvaluate_NegatedHasUnknownFieldFailOpen(t *testing.T) {
	result := Evaluate("-has:doesnt_exist", bareIssue())
	assert.True(t, result.Matched, "negated has: with unknown field should fail-open")
	assert.NotEmpty(t, result.Error)
	assert.Contains(t, result.Error, "unsupported has:doesnt_exist")
}

func TestEvaluate_NegatedNoUnknownFieldFailOpen(t *testing.T) {
	result := Evaluate("-no:doesnt_exist", bareIssue())
	assert.True(t, result.Matched, "negated no: with unknown field should fail-open")
	assert.NotEmpty(t, result.Error)
	assert.Contains(t, result.Error, "unsupported no:doesnt_exist")
}

// === Nil issue safety ===

func TestEvaluate_NilIssueFailOpen(t *testing.T) {
	result := Evaluate("label:bug", nil)
	assert.True(t, result.Matched)
	assert.NotEmpty(t, result.Error)
	assert.Contains(t, result.Error, "nil issue")
}

// === author:<login> ===

func TestEvaluate_MatchesAuthor(t *testing.T) {
	issue := issueWithAuthor("octocat")
	result := Evaluate("author:octocat", issue)
	assert.True(t, result.Matched)
}

func TestEvaluate_NoMatchAuthorWrong(t *testing.T) {
	issue := issueWithAuthor("octocat")
	result := Evaluate("author:mona", issue)
	assert.False(t, result.Matched)
}

func TestEvaluate_AuthorWithAtPrefix(t *testing.T) {
	issue := issueWithAuthor("octocat")
	result := Evaluate("author:@octocat", issue)
	assert.True(t, result.Matched)
}

func TestEvaluate_AuthorCaseInsensitive(t *testing.T) {
	issue := issueWithAuthor("octocat")
	result := Evaluate("author:OCTOCAT", issue)
	assert.True(t, result.Matched)
}

func TestEvaluate_AuthorNoUser(t *testing.T) {
	result := Evaluate("author:octocat", bareIssue())
	assert.False(t, result.Matched)
}

func TestEvaluate_NegatedAuthor(t *testing.T) {
	issue := issueWithAuthor("octocat")
	result := Evaluate("-author:mona", issue)
	assert.True(t, result.Matched)
}

// === milestone:<title> ===

func TestEvaluate_MatchesMilestone(t *testing.T) {
	issue := issueWithMilestone("v1.0")
	result := Evaluate("milestone:v1.0", issue)
	assert.True(t, result.Matched)
}

func TestEvaluate_NoMatchMilestoneWrong(t *testing.T) {
	issue := issueWithMilestone("v1.0")
	result := Evaluate("milestone:v2.0", issue)
	assert.False(t, result.Matched)
}

func TestEvaluate_MilestoneCaseInsensitive(t *testing.T) {
	issue := issueWithMilestone("Sprint-1")
	result := Evaluate("milestone:sprint-1", issue)
	assert.True(t, result.Matched)
}

func TestEvaluate_MilestoneNoMilestone(t *testing.T) {
	result := Evaluate("milestone:v1.0", bareIssue())
	assert.False(t, result.Matched)
}

func TestEvaluate_HasMilestoneWhenPresent(t *testing.T) {
	issue := issueWithMilestone("v1.0")
	result := Evaluate("has:milestone", issue)
	assert.True(t, result.Matched)
}

func TestEvaluate_HasMilestoneWhenAbsent(t *testing.T) {
	result := Evaluate("has:milestone", bareIssue())
	assert.False(t, result.Matched)
}

func TestEvaluate_NoMilestoneWhenAbsent(t *testing.T) {
	result := Evaluate("no:milestone", bareIssue())
	assert.True(t, result.Matched)
}

func TestEvaluate_NoMilestoneWhenPresent(t *testing.T) {
	issue := issueWithMilestone("v1.0")
	result := Evaluate("no:milestone", issue)
	assert.False(t, result.Matched)
}

// === type:<name> (issue type) ===

func TestEvaluate_MatchesType(t *testing.T) {
	issue := issueWithType("Bug")
	result := Evaluate("type:Bug", issue)
	assert.True(t, result.Matched)
}

func TestEvaluate_TypeCaseInsensitive(t *testing.T) {
	issue := issueWithType("Bug")
	result := Evaluate("type:bug", issue)
	assert.True(t, result.Matched)
}

func TestEvaluate_NoMatchTypeWrong(t *testing.T) {
	issue := issueWithType("Bug")
	result := Evaluate("type:Task", issue)
	assert.False(t, result.Matched)
}

func TestEvaluate_TypeNoType(t *testing.T) {
	result := Evaluate("type:Bug", bareIssue())
	assert.False(t, result.Matched)
}

func TestEvaluate_TypeIssueNoOp(t *testing.T) {
	result := Evaluate("type:issue", bareIssue())
	assert.True(t, result.Matched)
}

func TestEvaluate_TypePRRejected(t *testing.T) {
	result := Evaluate("type:pr", bareIssue())
	assert.False(t, result.Matched)
}

func TestEvaluate_HasTypeWhenPresent(t *testing.T) {
	issue := issueWithType("Bug")
	result := Evaluate("has:type", issue)
	assert.True(t, result.Matched)
}

func TestEvaluate_HasTypeWhenAbsent(t *testing.T) {
	result := Evaluate("has:type", bareIssue())
	assert.False(t, result.Matched)
}

func TestEvaluate_NoTypeWhenAbsent(t *testing.T) {
	result := Evaluate("no:type", bareIssue())
	assert.True(t, result.Matched)
}

func TestEvaluate_NoTypeWhenPresent(t *testing.T) {
	issue := issueWithType("Bug")
	result := Evaluate("no:type", issue)
	assert.False(t, result.Matched)
}

// === is: / state: qualifiers ===

func TestEvaluate_IsOpenAlwaysTrue(t *testing.T) {
	result := Evaluate("is:open", bareIssue())
	assert.True(t, result.Matched)
}

func TestEvaluate_StateOpenAlwaysTrue(t *testing.T) {
	result := Evaluate("state:open", bareIssue())
	assert.True(t, result.Matched)
}

func TestEvaluate_IsIssueNoOp(t *testing.T) {
	result := Evaluate("is:issue", bareIssue())
	assert.True(t, result.Matched)
}

func TestEvaluate_IsPRRejected(t *testing.T) {
	result := Evaluate("is:pr", bareIssue())
	assert.False(t, result.Matched)
}

// TestEvaluate_IsDraftFailsOpenForIssues guards against a regression where
// matchIs("draft") would dispatch to issueTarget.IsDraft() (always false)
// and silently reject every issue. is:draft is PR-only and should fail-open
// for issue targets.
func TestEvaluate_IsDraftFailsOpenForIssues(t *testing.T) {
	result := Evaluate("is:draft", bareIssue())
	assert.True(t, result.Matched)
}

func TestEvaluate_IsClosedAlwaysFalse(t *testing.T) {
	result := Evaluate("is:closed", bareIssue())
	assert.False(t, result.Matched)
}

func TestEvaluate_StateClosedAlwaysFalse(t *testing.T) {
	result := Evaluate("state:closed", bareIssue())
	assert.False(t, result.Matched)
}

// === Comma-separated label AND-matching ===

func TestEvaluate_CommaSeparatedLabelsBothPresent(t *testing.T) {
	issue := issueWithLabels("bug", "enhancement")
	result := Evaluate("label:bug,enhancement", issue)
	assert.True(t, result.Matched)
}

func TestEvaluate_CommaSeparatedLabelsOnlyOnePresent(t *testing.T) {
	issue := issueWithLabels("bug")
	result := Evaluate("label:bug,enhancement", issue)
	assert.False(t, result.Matched)
}

func TestEvaluate_CommaSeparatedLabelsNonePresent(t *testing.T) {
	result := Evaluate("label:bug,enhancement", bareIssue())
	assert.False(t, result.Matched)
}

// === Complex queries with new qualifiers ===

func TestEvaluate_AuthorAndLabel(t *testing.T) {
	issue := &gg.Issue{
		User:   &gg.User{Login: ptr("octocat")},
		Labels: []*gg.Label{{Name: ptr("bug")}},
	}
	result := Evaluate("author:octocat label:bug", issue)
	assert.True(t, result.Matched)
}

func TestEvaluate_MilestoneOrLabel(t *testing.T) {
	issue := issueWithMilestone("v1.0")
	result := Evaluate("milestone:v1.0 OR label:bug", issue)
	assert.True(t, result.Matched)
}

func TestEvaluate_NegatedTypeWithLabel(t *testing.T) {
	issue := &gg.Issue{
		Labels: []*gg.Label{{Name: ptr("auto-triage")}},
	}
	result := Evaluate("label:auto-triage -has:type", issue)
	assert.True(t, result.Matched)
}
