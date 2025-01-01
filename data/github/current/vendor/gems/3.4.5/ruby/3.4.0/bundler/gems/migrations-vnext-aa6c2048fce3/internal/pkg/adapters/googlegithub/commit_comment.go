package googlegithub

import (
	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
	"github.com/google/go-github/v65/github"
)

// CommitComment is a wrapper around the github.RepositoryComment struct which allows us
// to implement our own methods.
type CommitComment struct {
	github.RepositoryComment
}

// ToV1CommitComment converts a github.RepositoryComment to a v1.CommitComment.
func (r CommitComment) ToV1CommitComment() (*v1.CommitComment, error) {
	return &v1.CommitComment{
		ResourceId:     r.GetHTMLURL(),
		UserResourceId: r.GetUser().GetHTMLURL(),
		Path:           r.GetPath(),
		Body:           r.GetBody(),
		Position:       int64(r.GetPosition()),
		CreatedAt:      toTimestamp(r.CreatedAt),
	}, nil
}
