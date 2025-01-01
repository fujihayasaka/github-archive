package googlegithub

import (
	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
	"github.com/google/go-github/v65/github"
)

// IssueComment is a wrapper around the github.IssueComment struct which allows us
// to implement our own methods.
type IssueComment struct {
	github.IssueComment
}

// ToV1IssueComment converts a github.Issue to a v1.Issue.
func (r *IssueComment) ToV1IssueComment() (*v1.IssueComment, error) {
	return &v1.IssueComment{
		Body:           r.GetBody(),
		CreatedAt:      toTimestamp(r.CreatedAt),
		ResourceId:     r.GetHTMLURL(),
		UserResourceId: r.GetUser().GetHTMLURL(),
	}, nil
}
