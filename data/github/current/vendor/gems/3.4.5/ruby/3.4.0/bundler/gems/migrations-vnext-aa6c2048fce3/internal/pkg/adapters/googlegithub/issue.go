package googlegithub

import (
	"github.com/github/migrations-vnext/internal/pkg/set"
	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
	"github.com/google/go-github/v65/github"
)

// Issue is a wrapper around the github.Issue struct which allows us
// to implement our own methods.
type Issue struct {
	github.Issue
}

// ToV1Issue converts a github.Issue to a v1.Issue.
func (r *Issue) ToV1Issue() (*v1.Issue, error) {
	assigneeURLs := set.New[string]()

	// Conditional is to prevent an empty string from being added
	// to the set. An empty string in the AssigneesResourceIds
	// field causes an error at the Import API.
	if r.Assignee != nil {
		assigneeURLs.Add(r.GetAssignee().GetHTMLURL())
	}
	for _, assignee := range r.Assignees {
		assigneeURLs.Add(assignee.GetHTMLURL())
	}

	return &v1.Issue{
		AssigneesResourceIds: assigneeURLs.ToSlice(),
		Body:                 r.GetBody(),
		ClosedAt:             toTimestamp(r.ClosedAt),
		CreatedAt:            toTimestamp(r.CreatedAt),
		ResourceId:           r.GetHTMLURL(),
		Title:                r.GetTitle(),
		UpdatedAt:            toTimestamp(r.UpdatedAt),
		UserResourceId:       r.GetUser().GetHTMLURL(),
	}, nil
}
