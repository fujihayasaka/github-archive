// Package issuefilter evaluates GitHub search query filters against go-github
// Issue and PullRequest objects in-memory, using fail-open semantics.
package issuefilter

import (
	"fmt"
	"strings"

	gg "github.com/google/go-github/v75/github"
)

// Result holds the outcome of evaluating a filter query against an issue.
type Result struct {
	Matched bool
	Error   string
}

// evalContext accumulates warnings during AST evaluation so they can
// be surfaced in Result.Error without short-circuiting fail-open semantics.
type evalContext struct {
	warnings []string
}

func (ec *evalContext) warn(msg string) {
	ec.warnings = append(ec.warnings, msg)
}

// Evaluate evaluates the filter query against the given go-github Issue.
// It uses fail-open semantics: blank, invalid, or unparseable queries
// return a match so that issues are not silently skipped.
//
// Supported qualifiers:
//   - label:<name>       — issue has label with given name (comma-separated = AND)
//   - assignee:<login>   — issue is assigned to given user
//   - author:<login>     — issue was created by given user
//   - milestone:<title>  — issue has milestone with given title
//   - type:<name>        — issue type; type:issue is a no-op, type:pr always rejects
//   - is:open/issue      — always true for new issues; is:pr/closed always false
//   - state:open/closed  — same semantics as is:open/closed
//   - has:label/assignee/milestone/type — presence checks
//   - no:label/assignee/milestone/type  — absence checks
//
// Boolean operators: implicit AND (space-separated), explicit AND, OR
// Negation: -qualifier:value
// Unknown qualifiers match (fail-open, with error logged).
// Free-text tokens match (fail-open).
func Evaluate(query string, issue *gg.Issue) (result Result) {
	defer func() {
		if r := recover(); r != nil {
			result = Result{Matched: true, Error: fmt.Sprintf("filter evaluation panic: %v", r)}
		}
	}()

	if strings.TrimSpace(query) == "" {
		return Result{Matched: true}
	}

	if issue == nil {
		return Result{Matched: true, Error: "nil issue (fail-open)"}
	}

	return evaluateAgainst(query, issueTarget{issue: issue})
}

// EvaluatePR evaluates the filter query against the given go-github
// PullRequest. Same fail-open semantics as Evaluate. In addition to the
// issue-shared qualifiers (label, assignee, author, milestone, is, state,
// has, no, free text), the following pull-request-only qualifiers are
// supported: draft:true/false, base:<ref>, head:<ref>. The type: qualifier
// resolves type:pr → true and type:issue → false for PRs (the inverse of
// the issue evaluator's behaviour).
func EvaluatePR(query string, pr *gg.PullRequest) (result Result) {
	defer func() {
		if r := recover(); r != nil {
			result = Result{Matched: true, Error: fmt.Sprintf("filter evaluation panic: %v", r)}
		}
	}()

	if strings.TrimSpace(query) == "" {
		return Result{Matched: true}
	}

	if pr == nil {
		return Result{Matched: true, Error: "nil pull request (fail-open)"}
	}

	return evaluateAgainst(query, prTarget{pr: pr})
}

func evaluateAgainst(query string, target Target) Result {
	node, err := parse(query)
	if err != nil {
		return Result{Matched: true, Error: "invalid syntax: " + err.Error()}
	}

	ec := &evalContext{}
	matched := evalNode(ec, node, target)

	errMsg := ""
	if len(ec.warnings) > 0 {
		errMsg = strings.Join(ec.warnings, "; ")
	}
	return Result{Matched: matched, Error: errMsg}
}

// evalNode recursively evaluates an AST node against the target.
func evalNode(ec *evalContext, n node, target Target) bool {
	switch v := n.(type) {
	case *andNode:
		if len(v.children) == 0 {
			return true // empty AND = fail-open
		}
		for _, child := range v.children {
			if !evalNode(ec, child, target) {
				return false
			}
		}
		return true
	case *orNode:
		if len(v.children) == 0 {
			return false // empty OR = no match
		}
		for _, child := range v.children {
			if evalNode(ec, child, target) {
				return true
			}
		}
		return false
	case *qualifierNode:
		warningsBefore := len(ec.warnings)
		matched := matchQualifier(ec, v.field, v.value, target)
		// If a new warning was added (unsupported qualifier), fail-open regardless of negation.
		if len(ec.warnings) > warningsBefore {
			return true
		}
		if v.negated {
			return !matched
		}
		return matched
	case *textNode:
		return true // free-text is fail-open
	default:
		return true // unknown node type is fail-open
	}
}

// matchQualifier evaluates a single field:value qualifier against the target.
func matchQualifier(ec *evalContext, field, value string, target Target) bool {
	switch field {
	case "label":
		return matchLabel(value, target)
	case "assignee":
		return matchAssignee(value, target)
	case "author":
		return matchAuthor(value, target)
	case "milestone":
		return matchMilestone(value, target)
	case "type":
		return matchType(value, target)
	case "is":
		return matchIs(value, target)
	case "state":
		return matchState(value)
	case "has":
		return matchHas(ec, value, target)
	case "no":
		return matchNo(ec, value, target)
	case "draft":
		return matchDraft(ec, value, target)
	case "base":
		return matchRef(ec, "base", value, target.BaseRef(), target)
	case "head":
		return matchRef(ec, "head", value, target.HeadRef(), target)
	default:
		ec.warn(fmt.Sprintf("unsupported qualifier %q (fail-open)", field))
		return true
	}
}

func matchLabel(value string, target Target) bool {
	// Comma-separated labels use AND semantics: label:bug,enhancement
	// means the target must have BOTH labels.
	names := target.LabelNames()
	for part := range strings.SplitSeq(value, ",") {
		part = strings.TrimSpace(part)
		if part == "" {
			continue
		}
		if !containsFold(names, part) {
			return false
		}
	}
	return true
}

func containsFold(haystack []string, needle string) bool {
	for _, h := range haystack {
		if strings.EqualFold(h, needle) {
			return true
		}
	}
	return false
}

func matchAssignee(value string, target Target) bool {
	login := strings.TrimPrefix(value, "@")
	return containsFold(target.AssigneeLogins(), login)
}

func matchAuthor(value string, target Target) bool {
	login := strings.TrimPrefix(value, "@")
	author := target.AuthorLogin()
	if author == "" {
		return false
	}
	return equalsFold(author, login)
}

func matchMilestone(value string, target Target) bool {
	title := target.MilestoneTitle()
	if title == "" {
		return false
	}
	return equalsFold(title, value)
}

func matchType(value string, target Target) bool {
	lower := strings.ToLower(value)
	if lower == "pr" || lower == "pull_request" {
		return target.IsPullRequest()
	}
	if lower == "issue" {
		return !target.IsPullRequest()
	}
	if name := target.TypeName(); name != "" {
		return equalsFold(name, value)
	}
	return false
}

func matchIs(value string, target Target) bool {
	lower := strings.ToLower(value)
	switch lower {
	case "pr", "pull_request":
		return target.IsPullRequest()
	case "issue":
		return !target.IsPullRequest()
	case "draft":
		// is:draft is a PR-only qualifier — for issue targets, fail-open
		// to match the prior behaviour where unknown is: values fell through
		// to the default branch.
		if !target.IsPullRequest() {
			return true
		}
		return target.IsDraft()
	case "closed":
		return false // newly-created issues/PRs can never be closed
	}
	return true // is:open or unknown value: fail-open
}

func matchState(value string) bool {
	lower := strings.ToLower(value)
	if lower == "closed" {
		return false // newly-created issues/PRs can never be closed
	}
	return true // open or unknown state: value is fail-open
}

func matchHas(ec *evalContext, value string, target Target) bool {
	switch strings.ToLower(value) {
	case "label":
		return len(target.LabelNames()) > 0
	case "assignee":
		return len(target.AssigneeLogins()) > 0
	case "milestone":
		return target.HasMilestone()
	case "type":
		return target.HasType()
	default:
		ec.warn(fmt.Sprintf("unsupported has:%s qualifier (fail-open)", value))
		return true
	}
}

func matchNo(ec *evalContext, value string, target Target) bool {
	switch strings.ToLower(value) {
	case "label":
		return len(target.LabelNames()) == 0
	case "assignee":
		return len(target.AssigneeLogins()) == 0
	case "milestone":
		return !target.HasMilestone()
	case "type":
		return !target.HasType()
	default:
		ec.warn(fmt.Sprintf("unsupported no:%s qualifier (fail-open)", value))
		return true
	}
}

// matchDraft handles draft:true / draft:false on pull requests. For non-PR
// targets (issues) the qualifier is unsupported — warn and fail-open.
func matchDraft(ec *evalContext, value string, target Target) bool {
	if !target.IsPullRequest() {
		ec.warn("draft: qualifier is only supported on pull requests (fail-open)")
		return true
	}
	switch strings.ToLower(value) {
	case "true":
		return target.IsDraft()
	case "false":
		return !target.IsDraft()
	default:
		ec.warn(fmt.Sprintf("unsupported draft:%s value (fail-open)", value))
		return true
	}
}

// matchRef handles base:<ref> / head:<ref> on pull requests. For non-PR
// targets (issues) the qualifier is unsupported — warn and fail-open.
func matchRef(ec *evalContext, field, value, ref string, target Target) bool {
	if !target.IsPullRequest() {
		ec.warn(fmt.Sprintf("%s: qualifier is only supported on pull requests (fail-open)", field))
		return true
	}
	if ref == "" {
		return false
	}
	return equalsFold(ref, value)
}
