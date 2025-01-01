// Package keys contains types and functions for generating key
// identifiers based on fields of a resource.
package keys

import (
	"fmt"
	"net/url"
	"strconv"
	"strings"
)

type (
	// Convenient structs to represent the resource ids

	// OrganizationKey is the key for an organization
	OrganizationKey struct {
		Scheme         Scheme
		EnterpriseName string
		OrgLogin       string
	}

	// TeamKey is the key for an organization
	TeamKey struct {
		OrganizationKey
		TeamLogin string
	}

	// MannequinKey Mannequin is the key for a mannequin
	MannequinKey struct {
		Scheme         Scheme
		EnterpriseName string
		UserLogin      string
	}

	// RepositoryKey is the key for a repository
	RepositoryKey struct {
		OrganizationKey
		Name string
	}

	// IssueKey is the key for an issue
	IssueKey struct {
		RepositoryKey
		IsPullRequest bool
		Number        int64
	}

	// IssueCommentKey is the key for an issue comment
	IssueCommentKey struct {
		IssueKey
		CommentID int64
	}

	// IssueEventKey is the key for an issue event
	IssueEventKey struct {
		IssueKey
		EventID int64
	}

	// PullRequestKey is the key for a PR
	PullRequestKey IssueKey

	// PullRequestReviewKey is the key for a PR comment
	PullRequestReviewKey struct {
		PullRequestKey
		ReviewID      int64
		CrawlerFormat bool
	}

	// MilestoneKey is the key for a milestone
	MilestoneKey struct {
		RepositoryKey
		MilestoneID int64
	}

	// CommitCommentKey is the key for a commit comment
	CommitCommentKey struct {
		RepositoryKey
		CommitID  string
		CommentID int64
	}

	// Scheme is the scheme for the resource key
	Scheme int
)

const (
	// SchemeHTTP is the HTTP scheme
	SchemeHTTP Scheme = iota
	// SchemeHTTPS is the HTTPS scheme
	SchemeHTTPS
	// SchemeUnknown is an unknown scheme
	SchemeUnknown
)

// String returns the string representation of the organization key
func (o OrganizationKey) String() string {
	return fmt.Sprintf("%s://%s/%s", o.Scheme, o.EnterpriseName, o.OrgLogin)
}

// BaseURL returns the base URL for the organization key
func (o OrganizationKey) BaseURL() string {
	return fmt.Sprintf("%s://%s", o.Scheme, o.EnterpriseName)
}

// ToOrganizationKey returns the organization key from a string
// E.g: http://github.dev/acme
func ToOrganizationKey(s string) (OrganizationKey, error) {
	org := OrganizationKey{Scheme: toProto(s)}
	host, segments, err := parseURL(s, 1)
	if err != nil {
		return org, fmt.Errorf("failed to parse organization URL: %w", err)
	}
	org.EnterpriseName = host
	org.OrgLogin = segments[0]
	return org, nil
}

// String returns the string representation of the mannequin key
func (m MannequinKey) String() string {
	return fmt.Sprintf("%s://%s/%s", m.Scheme, m.EnterpriseName, m.UserLogin)
}

// ToMannequinKey returns the mannequin key from a string
func ToMannequinKey(s string) (MannequinKey, error) {
	m := MannequinKey{Scheme: toProto(s)}
	u, segments, err := parseURL(s, 1)
	if err != nil {
		return m, fmt.Errorf("failed to parse mannequin URL: %w", err)
	}
	m.EnterpriseName = u
	m.UserLogin = segments[0]
	return m, nil
}

// String returns the string representation of the repository key
func (r RepositoryKey) String() string {
	return fmt.Sprintf("%s://%s/%s/%s", r.Scheme, r.EnterpriseName, r.OrgLogin, r.Name)
}

// ToRepositoryKey returns the repository key from a string
func ToRepositoryKey(s string) (RepositoryKey, error) {
	var r RepositoryKey
	r.Scheme = toProto(s)
	host, segments, err := parseURL(s, 2)
	if err != nil {
		return r, fmt.Errorf("failed to parse repository URL: %w", err)
	}
	r.EnterpriseName = host
	r.OrgLogin = segments[0]
	r.Name = segments[1]
	return r, nil
}

// String returns the string representation of the issue key
func (i IssueKey) String() string {
	return fmt.Sprintf("%s://%s/%s/%s/%s/%d",
		i.Scheme, i.EnterpriseName, i.OrgLogin, i.Name, i.ResourceType(), i.Number)
}

// ToIssueKey returns the issue key from a string
func ToIssueKey(s string) (IssueKey, error) {
	var i IssueKey
	i.Scheme = toProto(s)
	host, segments, err := parseURL(s, 4)
	if err != nil {
		return i, fmt.Errorf("failed to parse issue URL: %w", err)
	}
	if segments[2] != "issues" {
		return i, fmt.Errorf("expected issues segment, got %s", segments[2])
	}
	i.RepositoryKey.EnterpriseName = host
	i.RepositoryKey.OrgLogin = segments[0]
	i.RepositoryKey.Name = segments[1]
	i.Number, err = strconv.ParseInt(segments[3], 10, 64)
	if err != nil {
		return i, fmt.Errorf("failed to parse issue number: %w", err)
	}
	return i, nil
}

// ResourceType returns the resource type for the issue key that can be either an issue or a pull request
func (i IssueKey) ResourceType() string {
	if i.IsPullRequest {
		return "pull"
	}
	return "issues"
}

// String returns the string representation of the issue comment key
func (i IssueCommentKey) String() string {
	return fmt.Sprintf("%s://%s/%s/%s/%s/%d#issuecomment-%d",
		i.Scheme, i.EnterpriseName, i.OrgLogin, i.Name, i.ResourceType(), i.Number, i.CommentID)
}

// ToIssueCommentKey returns the issue comment key from a string
func ToIssueCommentKey(s string) (IssueCommentKey, error) {
	var i IssueCommentKey
	i.Scheme = toProto(s)
	host, segments, err := parseURL(s, 4)
	if err != nil {
		return i, fmt.Errorf("failed to parse issue comment URL: %w", err)
	}
	i.OrganizationKey.EnterpriseName = host
	i.OrganizationKey.OrgLogin = segments[0]
	i.RepositoryKey.Name = segments[1]
	i.IsPullRequest = segments[2] == "pull"
	i.Number, err = strconv.ParseInt(segments[3], 10, 64)
	if err != nil {
		return i, fmt.Errorf("failed to parse issue number: %w", err)
	}
	parsed, err := url.Parse(s)
	if err != nil {
		return i, fmt.Errorf("failed to parse URL: %w", err)
	}
	tokens := strings.Split(parsed.Fragment, "issuecomment-")
	if len(tokens) != 2 {
		return i, fmt.Errorf("failed to parse fragment from  issue comment ID: %s", parsed.Fragment)
	}
	i.CommentID, err = strconv.ParseInt(tokens[1], 10, 64)
	if err != nil {
		return i, fmt.Errorf("failed to parse issue comment ID: %w", err)
	}
	return i, nil
}

// String returns the string representation of the issue comment key
func (i IssueEventKey) String() string {
	return fmt.Sprintf("%s://%s/%s/%s/issues/%d#event-%d",
		i.Scheme, i.EnterpriseName, i.OrgLogin, i.Name, i.Number, i.EventID)
}

// ToIssueEventKey returns the issue comment key from a string
func ToIssueEventKey(s string) (IssueEventKey, error) {
	var i IssueEventKey
	i.Scheme = toProto(s)
	host, segments, err := parseURL(s, 4)
	if err != nil {
		return i, fmt.Errorf("failed to parse issue comment URL: %w", err)
	}
	i.OrganizationKey.EnterpriseName = host
	i.OrganizationKey.OrgLogin = segments[0]
	i.RepositoryKey.Name = segments[1]
	i.Number, err = strconv.ParseInt(segments[3], 10, 64)
	if err != nil {
		return i, fmt.Errorf("failed to parse issue number: %w", err)
	}
	parsed, err := url.Parse(s)
	if err != nil {
		return i, fmt.Errorf("failed to parse URL: %w", err)
	}
	tokens := strings.Split(parsed.Fragment, "event-")
	if len(tokens) != 2 {
		return i, fmt.Errorf("failed to parse fragment from  issue event ID: %s", parsed.Fragment)
	}
	i.EventID, err = strconv.ParseInt(tokens[1], 10, 64)
	if err != nil {
		return i, fmt.Errorf("failed to parse issue event ID: %w", err)
	}
	return i, nil
}

// String returns the string representation of the pull request key
func (i PullRequestKey) String() string {
	return fmt.Sprintf("%s://%s/%s/%s/pull/%d",
		i.Scheme, i.EnterpriseName, i.OrgLogin, i.Name, i.Number)
}

// ToPullRequestKey returns the issue key from a string
func ToPullRequestKey(s string) (PullRequestKey, error) {
	var i PullRequestKey
	i.Scheme = toProto(s)
	host, segments, err := parseURL(s, 4)
	if err != nil {
		return i, fmt.Errorf("failed to parse PR URL: %w", err)
	}
	if segments[2] != "pull" {
		return i, fmt.Errorf("expected PR segment, got %s", segments[2])
	}
	i.RepositoryKey.EnterpriseName = host
	i.RepositoryKey.OrgLogin = segments[0]
	i.RepositoryKey.Name = segments[1]
	i.Number, err = strconv.ParseInt(segments[3], 10, 64)
	i.IsPullRequest = true
	if err != nil {
		return i, fmt.Errorf("failed to parse PR number: %w", err)
	}
	return i, nil
}

// String returns the string representation of the pull request key
func (i PullRequestReviewKey) String() string {
	switch i.CrawlerFormat {
	case true:
		return fmt.Sprintf("%s://%s/%s/%s/pull/%d#pullrequestreview-%d",
			i.Scheme, i.EnterpriseName, i.OrgLogin, i.Name, i.Number, i.ReviewID)
	default:
		return fmt.Sprintf("%s://%s/%s/%s/pull/%d/files#pullrequestreview-%d",
			i.Scheme, i.EnterpriseName, i.OrgLogin, i.Name, i.Number, i.ReviewID)
	}
}

// ToPullRequestReviewKey returns the pr review key from a string
func ToPullRequestReviewKey(s string) (PullRequestReviewKey, error) {
	var i PullRequestReviewKey

	numbSegs := numSegments(s)
	switch numbSegs {
	case 4:
		i.CrawlerFormat = true
	case 5:
		// archive format
	default:
		return PullRequestReviewKey{}, fmt.Errorf("failed to parse PR review URL as it contains a wrong number of segments: %s", s)
	}

	i.Scheme = toProto(s)
	host, segments, err := parseURL(s, numbSegs)
	if err != nil {
		return i, fmt.Errorf("failed to parse archive PR review URL: %w", err)
	}
	if segments[2] != "pull" {
		return i, fmt.Errorf("expected archive PR segment, got %s", segments[2])
	}
	i.RepositoryKey.EnterpriseName = host
	i.RepositoryKey.OrgLogin = segments[0]
	i.RepositoryKey.Name = segments[1]
	i.Number, err = strconv.ParseInt(segments[3], 10, 64)
	if err != nil {
		return i, fmt.Errorf("failed to parse archive PR number: %w", err)
	}
	i.IsPullRequest = true
	parsed, err := url.Parse(s)
	if err != nil {
		return i, fmt.Errorf("failed to parse URL: %w", err)
	}
	tokens := strings.Split(parsed.Fragment, "pullrequestreview-")
	if len(tokens) != 2 {
		return i, fmt.Errorf("failed to parse fragment from archive pr review ID: %s", parsed.Fragment)
	}
	i.ReviewID, err = strconv.ParseInt(tokens[1], 10, 64)
	if err != nil {
		return i, fmt.Errorf("failed to parse archive pr review ID: %w", err)
	}
	return i, nil
}

// String returns the string representation of the team key
func (t TeamKey) String() string {
	return fmt.Sprintf("%s://%s/orgs/%s/teams/%s",
		t.Scheme, t.EnterpriseName, t.OrgLogin, t.TeamLogin)
}

// ToTeamKey returns the team key from a string
func ToTeamKey(s string) (TeamKey, error) {
	var t TeamKey
	t.Scheme = toProto(s)
	host, segments, err := parseURL(s, 4)
	if err != nil {
		return t, fmt.Errorf("failed to parse team URL: %w", err)
	}
	t.OrganizationKey.EnterpriseName = host
	t.OrganizationKey.OrgLogin = segments[1]
	t.TeamLogin = segments[3]
	return t, nil
}

// String returns the string representation of the milestone key
func (m MilestoneKey) String() string {
	return fmt.Sprintf(
		"%s://%s/%s/%s/milestones/%d",
		m.Scheme, m.EnterpriseName, m.OrgLogin, m.Name, m.MilestoneID,
	)
}

// ToMilestoneKey returns the milestone key from a string
func ToMilestoneKey(s string) (MilestoneKey, error) {
	var m MilestoneKey
	m.Scheme = toProto(s)
	host, segments, err := parseURL(s, 4)
	if err != nil {
		return m, fmt.Errorf("failed to parse milestone URL: %w", err)
	}
	m.EnterpriseName = host
	m.OrgLogin = segments[0]
	m.RepositoryKey.Name = segments[1]
	m.MilestoneID, err = strconv.ParseInt(segments[3], 10, 64)
	if err != nil {
		return m, fmt.Errorf("failed to parse milestone ID: %w", err)
	}
	return m, nil
}

// String returns the string representation of the commit comment key
func (i CommitCommentKey) String() string {
	return fmt.Sprintf("%s://%s/%s/%s/commit/%s#commitcomment-%d",
		i.Scheme, i.EnterpriseName, i.OrgLogin, i.Name, i.CommitID, i.CommentID)
}

// ToCommitCommentKey returns the commit comment key from a string
func ToCommitCommentKey(s string) (CommitCommentKey, error) {
	var i CommitCommentKey
	i.Scheme = toProto(s)
	host, segments, err := parseURL(s, 4)
	if err != nil {
		return i, fmt.Errorf("failed to parse commit comment URL: %w", err)
	}
	i.OrganizationKey.EnterpriseName = host
	i.OrganizationKey.OrgLogin = segments[0]
	i.RepositoryKey.Name = segments[1]
	i.CommitID = segments[3]

	parsed, err := url.Parse(s)
	if err != nil {
		return i, fmt.Errorf("failed to parse URL: %w", err)
	}
	tokens := strings.Split(parsed.Fragment, "commitcomment-")
	if len(tokens) != 2 {
		return i, fmt.Errorf("failed to parse fragment from  commit comment ID: %s", parsed.Fragment)
	}
	i.CommentID, err = strconv.ParseInt(tokens[1], 10, 64)
	if err != nil {
		return i, fmt.Errorf("failed to parse commit comment ID: %w", err)
	}
	return i, nil
}

// parseURL parses a URL and returns the host and segments, ensuring that the number of segments is as expected
func parseURL(u string, expectedSegments int) (host string, segments []string, err error) {
	parsed, err := url.Parse(u)
	if err != nil {
		return host, segments, fmt.Errorf("failed to parse URL: %w", err)
	}
	host = parsed.Host
	segments = strings.Split(strings.TrimPrefix(parsed.Path, "/"), "/")
	if len(segments) != expectedSegments {
		return host, segments, fmt.Errorf("expected %d segments, got %d", expectedSegments, len(segments))
	}
	return host, segments, nil
}

// numSegments returns the number of segments in the URL
func numSegments(u string) int {
	parsed, _ := url.Parse(u)
	return len(strings.Split(strings.TrimPrefix(parsed.Path, "/"), "/"))
}

// toProto returns the scheme for the given string
func toProto(s string) Scheme {
	if strings.HasPrefix(s, "https://") {
		return SchemeHTTPS
	}
	if strings.HasPrefix(s, "http://") {
		return SchemeHTTP
	}
	return SchemeUnknown
}

// String returns the string representation of the scheme
func (s Scheme) String() string {
	switch s {
	case SchemeHTTP:
		return "http"
	case SchemeHTTPS:
		return "https"
	default:
		return "unknown"
	}
}

// GitDataResourceID returns the resource ID for the git data pushed resource
func GitDataResourceID(k RepositoryKey) string {
	return fmt.Sprintf("virtual://%s/%s/%s/git-data-pushed", k.EnterpriseName, k.OrgLogin, k.Name)
}
