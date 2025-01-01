package googlegithub

import (
	"sort"

	"github.com/github/migrations-vnext/internal/pkg/set"
	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
	"github.com/google/go-github/v65/github"
)

// PullRequest is a wrapper around the github.PullRequest struct which allows us
// to implement our own methods.
type PullRequest struct {
	github.PullRequest
}

// ToV1PullRequest converts a github.PullRequest to a v1.PullRequest.
func (r *PullRequest) ToV1PullRequest() (*v1.PullRequest, error) {
	assignees, reviewers := set.New[string](), set.New[string]()

	if r.Assignee != nil {
		assignees.Add(r.GetAssignee().GetHTMLURL())
	}
	for _, assignee := range r.Assignees {
		assignees.Add(assignee.GetHTMLURL())
	}

	for _, reviewer := range r.RequestedReviewers {
		reviewers.Add(reviewer.GetHTMLURL())
	}

	assigneesSlice := assignees.ToSlice()
	reviewersSlice := reviewers.ToSlice()
	sort.Slice(assigneesSlice, func(i, j int) bool { return assigneesSlice[i] < assigneesSlice[j] })
	sort.Slice(reviewersSlice, func(i, j int) bool { return reviewersSlice[i] < reviewersSlice[j] })

	return &v1.PullRequest{
		ResourceId:           r.GetHTMLURL(),
		UserResourceId:       r.GetUser().GetHTMLURL(),
		AssigneesResourceIds: assigneesSlice,
		ReviewersResourceIds: reviewersSlice,
		Title:                r.GetTitle(),
		Body:                 r.GetBody(),
		IsDraft:              r.GetDraft(),
		BaseRef: &v1.RefDetails{
			Name:      r.GetBase().GetRef(),
			CommitSha: r.GetBase().GetSHA(),
		},
		HeadRef: &v1.RefDetails{
			Name:      r.GetHead().GetRef(),
			CommitSha: r.GetHead().GetSHA(),
		},
		MergeCommitSha:        r.GetMergeCommitSHA(),
		ClosedAt:              toTimestamp(r.ClosedAt),
		CreatedAt:             toTimestamp(r.CreatedAt),
		MergedAt:              toTimestamp(r.MergedAt),
		AttachmentResourceIds: nil,
	}, nil
}
