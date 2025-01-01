package resource

// Type is an enum for the resource type
type Type int

const (
	// TypeOrganization is the organization resource type
	TypeOrganization Type = iota
	// TypeTeam is the team resource type
	TypeTeam
	// TypeUser is the mannequin resource type
	TypeUser
	// TypeRepository is the repository resource type
	TypeRepository
	// TypeProtectedBranch is the protected branch resource type
	TypeProtectedBranch
	// TypeIssue is the issue resource type
	TypeIssue
	// TypeIssueComment is the issue comment resource type
	TypeIssueComment
	// TypeIssueEvent is the issue event resource type
	TypeIssueEvent
	// TypeMilestone is the milestone resource type
	TypeMilestone
	// TypePullRequest is the pull request resource type
	TypePullRequest
	// TypeProject is the project resource type
	TypeProject
	// TypeAttachment is the attachment resource type
	TypeAttachment
	// TypeLabel is the label resource type
	TypeLabel
	// TypeCommitComment is the commit comment resource type
	TypeCommitComment
	// TypeNoop is the noop resource type
	TypeNoop
	// TypeReactions is the reactions resource type
	TypeReactions
	// TypePullRequestReview is the pull request review resource type
	TypePullRequestReview
	// TypeRelease is the release resource type
	TypeRelease
	// TypeUnknown is the unknown resource type
	TypeUnknown
)

// String returns the string representation of a resource type
func (r Type) String() string {
	switch r {
	case TypeOrganization:
		return "organization"
	case TypeTeam:
		return "team"
	case TypeUser:
		return "user"
	case TypeRepository:
		return "repository"
	case TypeProtectedBranch:
		return "protected_branch"
	case TypeIssue:
		return "issue"
	case TypeIssueComment:
		return "issue_comment"
	case TypeIssueEvent:
		return "issue_event"
	case TypeMilestone:
		return "milestone"
	case TypePullRequest:
		return "pull_request"
	case TypeProject:
		return "project"
	case TypeAttachment:
		return "attachment"
	case TypeLabel:
		return "label"
	case TypeCommitComment:
		return "commit_comment"
	case TypeNoop:
		return "noop"
	case TypeReactions:
		return "reactions"
	case TypePullRequestReview:
		return "pull_request_review"
	case TypeRelease:
		return "release"
	default:
		return "unknown"
	}
}

// ToType returns the resource type from a string
func ToType(s string) Type {
	switch s {
	case "organization":
		return TypeOrganization
	case "team":
		return TypeTeam
	case "user":
		return TypeUser
	case "repository":
		return TypeRepository
	case "protected_branch":
		return TypeProtectedBranch
	case "issue":
		return TypeIssue
	case "issue_comment":
		return TypeIssueComment
	case "issue_event":
		return TypeIssueEvent
	case "milestone":
		return TypeMilestone
	case "pull_request":
		return TypePullRequest
	case "project":
		return TypeProject
	case "attachment":
		return TypeAttachment
	case "label":
		return TypeLabel
	case "commit_comment":
		return TypeCommitComment
	case "noop":
		return TypeNoop
	case "reactions":
		return TypeReactions
	case "pull_request_review":
		return TypePullRequestReview
	case "release":
		return TypeRelease
	default:
		return TypeUnknown
	}
}

// ToTypeSet returns a set of resource types
func ToTypeSet(t ...Type) map[Type]struct{} {
	m := make(map[Type]struct{})
	for _, t := range t {
		m[t] = struct{}{}
	}
	return m
}
