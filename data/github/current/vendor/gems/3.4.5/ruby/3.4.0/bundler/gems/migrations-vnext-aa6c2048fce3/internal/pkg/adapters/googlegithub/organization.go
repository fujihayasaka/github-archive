package googlegithub

import (
	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
	"github.com/google/go-github/v65/github"
)

// Organization is a wrapper around github.Organization struct which allows us
// to implement our own methods.
type Organization struct {
	github.Organization
}

const fetchUserIDFromMigrationContext = 0

// ToV1OrganizationWithUserID converts a github.Organization to a v1.Organization
func (r *Organization) ToV1Organization() (*v1.Organization, error) {
	name := r.GetName()
	if name == "" {
		name = r.GetLogin()
	}
	return &v1.Organization{
		Login:      r.GetLogin(),
		Name:       name,
		ResourceId: r.GetHTMLURL(),
	}, nil
}
