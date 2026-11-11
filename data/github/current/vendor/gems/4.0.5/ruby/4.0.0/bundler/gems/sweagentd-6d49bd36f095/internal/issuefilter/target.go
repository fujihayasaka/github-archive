package issuefilter

import (
	"strings"

	gg "github.com/google/go-github/v75/github"
)

// Target is the read-only view of an issue or pull request that match
// qualifiers operate on. Both *gg.Issue and *gg.PullRequest are adapted
// to this interface so the same query syntax can filter either kind.
//
//nolint:interfacebloat // Each method maps directly to a search-qualifier field; splitting yields no caller benefit.
type Target interface {
	LabelNames() []string
	AssigneeLogins() []string
	AuthorLogin() string
	MilestoneTitle() string
	HasMilestone() bool
	TypeName() string
	HasType() bool
	IsPullRequest() bool
	IsDraft() bool
	BaseRef() string
	HeadRef() string
}

// issueTarget adapts *gg.Issue to Target.
type issueTarget struct{ issue *gg.Issue }

func (t issueTarget) LabelNames() []string {
	out := make([]string, 0, len(t.issue.Labels))
	for _, l := range t.issue.Labels {
		if l != nil && l.Name != nil {
			out = append(out, *l.Name)
		}
	}
	return out
}

func (t issueTarget) AssigneeLogins() []string {
	out := make([]string, 0, len(t.issue.Assignees))
	for _, a := range t.issue.Assignees {
		if a != nil && a.Login != nil {
			out = append(out, *a.Login)
		}
	}
	return out
}

func (t issueTarget) AuthorLogin() string {
	if t.issue.User != nil && t.issue.User.Login != nil {
		return *t.issue.User.Login
	}
	return ""
}

func (t issueTarget) MilestoneTitle() string {
	if t.issue.Milestone != nil && t.issue.Milestone.Title != nil {
		return *t.issue.Milestone.Title
	}
	return ""
}

func (t issueTarget) HasMilestone() bool { return t.issue.Milestone != nil }

func (t issueTarget) TypeName() string {
	if t.issue.Type != nil && t.issue.Type.Name != nil {
		return *t.issue.Type.Name
	}
	return ""
}

func (t issueTarget) HasType() bool     { return t.issue.Type != nil }
func (issueTarget) IsPullRequest() bool { return false }
func (issueTarget) IsDraft() bool       { return false }
func (issueTarget) BaseRef() string     { return "" }
func (issueTarget) HeadRef() string     { return "" }

// prTarget adapts *gg.PullRequest to Target.
type prTarget struct{ pr *gg.PullRequest }

func (t prTarget) LabelNames() []string {
	out := make([]string, 0, len(t.pr.Labels))
	for _, l := range t.pr.Labels {
		if l != nil && l.Name != nil {
			out = append(out, *l.Name)
		}
	}
	return out
}

func (t prTarget) AssigneeLogins() []string {
	out := make([]string, 0, len(t.pr.Assignees))
	for _, a := range t.pr.Assignees {
		if a != nil && a.Login != nil {
			out = append(out, *a.Login)
		}
	}
	return out
}

func (t prTarget) AuthorLogin() string {
	if t.pr.User != nil && t.pr.User.Login != nil {
		return *t.pr.User.Login
	}
	return ""
}

func (t prTarget) MilestoneTitle() string {
	if t.pr.Milestone != nil && t.pr.Milestone.Title != nil {
		return *t.pr.Milestone.Title
	}
	return ""
}

func (t prTarget) HasMilestone() bool { return t.pr.Milestone != nil }

// TypeName for pull requests is empty — PRs do not carry a type field
// in the GitHub API.
func (prTarget) TypeName() string { return "" }
func (prTarget) HasType() bool    { return false }

func (prTarget) IsPullRequest() bool { return true }

func (t prTarget) IsDraft() bool {
	return t.pr.Draft != nil && *t.pr.Draft
}

func (t prTarget) BaseRef() string {
	if t.pr.Base != nil && t.pr.Base.Ref != nil {
		return *t.pr.Base.Ref
	}
	return ""
}

func (t prTarget) HeadRef() string {
	if t.pr.Head != nil && t.pr.Head.Ref != nil {
		return *t.pr.Head.Ref
	}
	return ""
}

// equalsFold is a small helper used by ref matchers to keep call sites tidy.
func equalsFold(a, b string) bool { return strings.EqualFold(a, b) }
