package archive

import (
	"fmt"
	"strings"
	"time"

	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
	"github.com/google/uuid"
)

// RefDetails represents the details of a reference
type RefDetails struct {
	Ref  string `json:"ref"`
	Sha  string `json:"sha"`
	User string `json:"user"`
	Repo string `json:"repo"`
}

// ReviewRequest represents a review request
type ReviewRequest struct {
	Reviewer     string    `json:"reviewer"`
	ReviewerType string    `json:"reviewer_type"`
	CreatedAt    time.Time `json:"created_at"`
	UpdatedAt    time.Time `json:"updated_at"`
	DismissedAt  time.Time `json:"dismissed_at"`
}

// CloseIssueReference represents a reference to a closed issue
type CloseIssueReference struct {
	Issue           string    `json:"issue"`
	IssueRepository string    `json:"issue_repository"`
	Actor           string    `json:"actor"`
	Source          string    `json:"source"`
	CreatedAt       time.Time `json:"created_at"`
}

// PullRequest represents a pull request in a GitHub repository
type PullRequest struct {
	Type                 string                `json:"type"`
	URL                  string                `json:"url"`
	User                 string                `json:"user"`
	Repository           string                `json:"repository"`
	Title                string                `json:"title"`
	Body                 string                `json:"body"`
	Base                 RefDetails            `json:"base"`
	Head                 RefDetails            `json:"head"`
	MergeCommitSha       string                `json:"merge_commit_sha"`
	Assignee             string                `json:"assignee"`
	Assignees            []string              `json:"assignees"`
	Milestone            string                `json:"milestone"`
	Labels               []string              `json:"labels"`
	Reactions            Reactions             `json:"reactions"`
	ReviewRequests       []ReviewRequest       `json:"review_requests"`
	CloseIssueReferences []CloseIssueReference `json:"close_issue_references"`
	WorkInProgress       bool                  `json:"work_in_progress"`
	MergedAt             time.Time             `json:"merged_at"`
	ClosedAt             time.Time             `json:"closed_at"`
	CreatedAt            time.Time             `json:"created_at"`
}

// ToV1PullRequest converts an archive Issue to a v1.PullRequest
func (r *PullRequest) ToV1PullRequest() (*v1.PullRequest, error) {
	assignees := addDedup(r.Assignees, r.Assignee)

	// Convert review requests
	var reviewers []string
	for _, reviewRequest := range r.ReviewRequests {
		if reviewRequest.ReviewerType != "User" {
			continue
		}
		reviewers = append(reviewers, reviewRequest.Reviewer)
	}
	reviewers = dedup(reviewers)

	return &v1.PullRequest{
		ResourceId:     r.URL,
		UserResourceId: r.User,
		Title:          r.Title,
		Body:           r.Body,
		IsDraft:        r.WorkInProgress,
		BaseRef: &v1.RefDetails{
			Name:      r.Base.Ref,
			CommitSha: r.Base.Sha,
		},
		HeadRef: &v1.RefDetails{
			Name:      r.Head.Ref,
			CommitSha: r.Head.Sha,
		},
		AssigneesResourceIds: assignees,
		ReviewersResourceIds: reviewers,
		CreatedAt:            toTimestamp(r.CreatedAt),
		ClosedAt:             toTimestamp(r.ClosedAt),
		MergedAt:             toTimestamp(r.MergedAt),
		MergeCommitSha:       r.MergeCommitSha,
	}, nil
}

// IsFromFork returns true if the pull request is from a fork by looking at the base and head ref names
func (r *PullRequest) IsFromFork() bool {
	return strings.Contains(r.Base.Ref, ":") || strings.Contains(r.Head.Ref, ":")
}

// ExtractV1CloseIssueReferences extracts and converts close issue references from a pull request.
func (r *PullRequest) ExtractV1CloseIssueReferences() []*v1.CloseIssueReference {
	var refs []*v1.CloseIssueReference

	for _, ref := range r.CloseIssueReferences {
		refs = append(refs, &v1.CloseIssueReference{
			ResourceId:            fmt.Sprintf("%s:%s", r.URL, ref.Issue),
			PullRequestResourceId: r.URL,
			IssueResourceId:       ref.Issue,
		})
	}
	return refs
}

func prepareCloseIssueReferenceBatches(refs []*v1.CloseIssueReference, batchSize int) []*v1.CloseIssueReferenceBatch {
	if batchSize <= 0 {
		return nil
	}
	batches := []*v1.CloseIssueReferenceBatch{}
	currentBatch := &v1.CloseIssueReferenceBatch{}
	addBatch := func() {
		if len(currentBatch.CloseIssueReferences) == 0 {
			return
		}
		currentBatch.ResourceId = fmt.Sprintf("close-issue-reference-batch-%s", uuid.New().String())
		batches = append(batches, currentBatch)
		currentBatch = &v1.CloseIssueReferenceBatch{}
	}

	for _, ref := range refs {
		currentBatch.CloseIssueReferences = append(currentBatch.CloseIssueReferences, ref)
		if len(currentBatch.CloseIssueReferences) >= batchSize {
			addBatch()
		}
	}

	addBatch()
	return batches
}
