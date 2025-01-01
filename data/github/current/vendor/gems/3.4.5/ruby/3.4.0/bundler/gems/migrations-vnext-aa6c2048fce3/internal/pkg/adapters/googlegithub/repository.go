package googlegithub

import (
	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
	"github.com/google/go-github/v65/github"
)

// Repository is a wrapper around github.Repository struct which allows us
// to implement our own methods.
type Repository struct {
	github.Repository
}

// ToV1RepositoryWithUserID converts a github.Repository to a v1.Repository
func (r *Repository) ToV1Repository() (*v1.Repository, error) {
	return &v1.Repository{
		ResourceId: r.GetHTMLURL(),
		IsPrivate:  r.GetPrivate(),
	}, nil
}
