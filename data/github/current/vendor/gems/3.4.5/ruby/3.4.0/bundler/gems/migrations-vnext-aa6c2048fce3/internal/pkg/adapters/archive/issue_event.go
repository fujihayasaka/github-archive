package archive

import (
	"fmt"
	"slices"
	"strings"
	"time"

	"github.com/github/migrations-vnext/internal/pkg/keys"
	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
)

// IssueEvent represents an issue event in a GitHub repository
type IssueEvent struct {
	URL                    string    `json:"url"`
	Issue                  string    `json:"issue"`
	PullRequest            string    `json:"pull_request"`
	Actor                  string    `json:"actor"`
	Subject                string    `json:"subject"`
	Event                  string    `json:"event"`
	ReferencingPullRequest string    `json:"referencing_pull_request"`
	CreatedAt              time.Time `json:"created_at"`
	LabelName              string    `json:"label_name"`
	TitleIs                string    `json:"title_is"`
	TitleWas               string    `json:"title_was"`
	MilestoneTitle         string    `json:"milestone_title"`
	ColumnName             string    `json:"column_name"`
	PreviousColumnName     string    `json:"previous_column_name"`
	LockReason             string    `json:"lock_reason"`
	BlockDurationDays      int64     `json:"block_duration_days"`
	Message                string    `json:"message"`
	CommitID               string    `json:"commit_id"`
	CommitRepository       string    `json:"commit_repository"`
	BeforeCommitOID        string    `json:"before_commit_oid"`
	AfterCommitOID         string    `json:"after_commit_oid"`
	Ref                    string    `json:"ref"`
}

// unsupportedIssueEvents is a list of issue events that are not supported for now
var unsupportedIssueEvents = []string{
	"added_to_project", "moved_columns_in_project", "removed_from_project", "converted_note_to_issue",
}

// ToV1IssueEvent converts an archive IssueEvent to a v1.IssueEvent
func (r *IssueEvent) ToV1IssueEvent() (*v1.IssueEvent, error) {
	i := &v1.IssueEvent{
		ResourceId:                       r.URL,
		ActorResourceId:                  r.Actor,
		ReferencingPullRequestResourceId: r.ReferencingPullRequest,
		CommitRepositoryResourceId:       r.CommitRepository,
		CommitId:                         r.CommitID,
		BeforeCommitOid:                  r.BeforeCommitOID,
		AfterCommitOid:                   r.AfterCommitOID,
		Ref:                              r.Ref,
		Event:                            r.Event,
		CreatedAt:                        toTimestamp(r.CreatedAt),
		LabelName:                        r.LabelName,
		TitleIs:                          r.TitleIs,
		TitleWas:                         r.TitleWas,
		MilestoneTitle:                   r.MilestoneTitle,
		ColumnName:                       r.ColumnName,
		PreviousColumnName:               r.PreviousColumnName,
		LockReason:                       r.LockReason,
		BlockDurationDays:                r.BlockDurationDays,
		Message:                          r.Message,
	}
	switch {
	case IsSubjectIssue(r.Subject):
		i.SubjectIssueResourceId = r.Subject
	case IsSubjectPullRequest(r.Subject):
		i.SubjectPullRequestResourceId = r.Subject
	case IsSubjectUser(r.Subject):
		i.SubjectUserResourceId = r.Subject
	}
	return i, nil
}

// IsSupported returns true if the issue event is supported, for now we only support some issue events.
// We don't support pull request events yet or issue events that reference PRs as the support doesn't
// seem to be complete yet in the API.
//
// Mentioned events are not supported if the actor is empty
func (r *IssueEvent) IsSupported() bool {
	if r.Event == "mentioned" && r.Actor == "" {
		return false
	}
	return r.ReferencingPullRequest == "" && !slices.Contains(unsupportedIssueEvents, r.Event)
}

// IsSubjectIssue returns true if the subject is an issue
func IsSubjectIssue(subject string) bool {
	_, err := keys.ToIssueKey(subject)
	return err == nil
}

// IsSubjectPullRequest returns true if the subject is a pull request
func IsSubjectPullRequest(subject string) bool {
	_, err := keys.ToPullRequestKey(subject)
	return err == nil
}

// IsSubjectUser returns true if the subject is an issue
func IsSubjectUser(subject string) bool {
	_, err := keys.ToMannequinKey(subject)
	return err == nil
}

// IsIssue returns true if the issue event is an issue event
func (r *IssueEvent) IsIssue() bool {
	return r.Issue != ""
}

// IsPullRequest returns true if the issue event is a pull request event
func (r *IssueEvent) IsPullRequest() bool {
	return r.PullRequest != ""
}

// repoKeysFromIssueEvent returns the repository keys for the given issue event.
func repoKeysFromIssueEvent(e *v1.IssueEvent) ([]keys.RepositoryKey, error) {
	var repoKeys []keys.RepositoryKey
	if e.SubjectIssueResourceId != "" {
		k, err := keys.ToIssueKey(e.SubjectIssueResourceId)
		if err != nil {
			return nil, fmt.Errorf("error converting issue key: %w", err)
		}
		repoKeys = append(repoKeys, k.RepositoryKey)
	}
	if e.SubjectPullRequestResourceId != "" {
		k, err := keys.ToPullRequestKey(e.SubjectPullRequestResourceId)
		if err != nil {
			return nil, fmt.Errorf("error converting pr key: %w", err)
		}
		repoKeys = append(repoKeys, k.RepositoryKey)
	}
	if e.ReferencingPullRequestResourceId != "" {
		k, err := keys.ToPullRequestKey(e.ReferencingPullRequestResourceId)
		if err != nil {
			return nil, fmt.Errorf("error converting pull request key: %w", err)
		}
		repoKeys = append(repoKeys, k.RepositoryKey)
	}
	return repoKeys, nil
}

// isSameRepoKeys returns true if the two slices of repository keys are the same.
func isSameRepoKeys(a, b []keys.RepositoryKey) bool {
	if len(b) != len(a) {
		return false
	}
	slices.SortFunc(a, func(i, j keys.RepositoryKey) int {
		return strings.Compare(i.String(), j.String())
	})
	slices.SortFunc(b, func(i, j keys.RepositoryKey) int {
		return strings.Compare(i.String(), j.String())
	})
	return slices.Equal(a, b)
}
