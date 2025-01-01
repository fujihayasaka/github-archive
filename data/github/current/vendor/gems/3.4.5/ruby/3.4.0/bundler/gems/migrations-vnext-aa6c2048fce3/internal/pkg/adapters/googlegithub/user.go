package googlegithub

import (
	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
	"github.com/google/go-github/v65/github"
)

// User is a wrapper around github.User struct which allows us
// to implement our own methods.
type User struct {
	github.User
}

// ToV1Mannequin converts a github.User to a v1.Mannequin.
func (r *User) ToV1Mannequin(orgID string) (*v1.Mannequin, error) {
	user := &v1.Mannequin{
		Email:         r.GetEmail(),
		OrgResourceId: orgID,
		ProfileName:   r.GetName(),
		ResourceId:    r.GetHTMLURL(),
	}

	return user, nil
}
