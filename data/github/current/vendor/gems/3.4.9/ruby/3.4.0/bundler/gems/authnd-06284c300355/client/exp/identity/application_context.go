package identity

import "fmt"

const (
	PersonalAccessTokenApplicationID   = 0
	PersonalAccessTokenApplicationType = ApplicationTypeOauthApplication
	PersonalAccessTokenClientID        = "00000000000000000000"
)

type ApplicationType string

const (
	ApplicationTypeIntegration      ApplicationType = "Integration"
	ApplicationTypeOauthApplication ApplicationType = "OauthApplication"
)

type ApplicationOwnerType string

const (
	// ApplicationOwnerTypeUser is the owner type for an application owned by a user
	// Note that it is _not_ to be used as a representation of the underlying table like the monolith does.
	// i.e. "User" means it is owned by a legitimate user, never an Organization.
	ApplicationOwnerTypeUser ApplicationOwnerType = "User"

	// ApplicationOwnerTypeOrganization is the owner type for an application owned by an organization
	ApplicationOwnerTypeOrganization ApplicationOwnerType = "Organization"

	// ApplicationOwnerTypeBusiness is the owner type for an application owned by a business
	ApplicationOwnerTypeBusiness ApplicationOwnerType = "Business"
)

// ApplicationContext is a struct that represents the context of an application
// an "application" can be an integration (GitHub Apps) _or_ an oauth application (OAuth Apps)
type ApplicationContext struct {
	ID        uint64
	Type      ApplicationType
	OwnerID   uint64
	OwnerType ApplicationOwnerType
}

func NewApplicationContext(id uint64, typ ApplicationType, ownerID uint64, ownerType ApplicationOwnerType) *ApplicationContext {
	return &ApplicationContext{
		ID:        id,
		Type:      typ,
		OwnerID:   ownerID,
		OwnerType: ownerType,
	}
}

func ParseApplicationOwnerType(val string) (ApplicationOwnerType, error) {
	switch val {
	case string(ApplicationOwnerTypeUser):
		return ApplicationOwnerTypeUser, nil
	case string(ApplicationOwnerTypeOrganization):
		return ApplicationOwnerTypeOrganization, nil
	case string(ApplicationOwnerTypeBusiness):
		return ApplicationOwnerTypeBusiness, nil
	default:
		return "", fmt.Errorf("invalid application owner type: %s", val)
	}
}
