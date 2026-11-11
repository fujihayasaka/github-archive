// Package extensions provides custom extensions to vexi to support specific use cases.
package extensions

import (
	"fmt"
	"strconv"

	"github.com/github/feature-management-client-go/vexi/v2"
)

// concreteActor is a helper for a default concrete actor.
type concreteActor struct {
	actorType string
	actorID   string
}

// newConcreteActor constructs an Vexi Actor from a type and ID
func newConcreteActor(actorType, actorID string) vexi.Actor {
	return &concreteActor{
		actorType: actorType,
		actorID:   actorID,
	}
}

// VexiID returns a valid Vexi actor identifier in the format TYPE:VALUE
func (a *concreteActor) VexiID() string {
	return fmt.Sprintf("%s:%s", a.actorType, a.actorID)
}

// NewUser creates an Vexi Actor from a User ID.
func NewUser(userID string) vexi.Actor {
	return newConcreteActor("User", userID)
}

// NewOrganization creates an Actor from a Organization ID.
func NewOrganization(organizationID string) vexi.Actor {
	return newConcreteActor("Organization", organizationID)
}

// NewBusiness creates an Actor from a Business ID.
func NewBusiness(businessID string) vexi.Actor {
	return newConcreteActor("Business", businessID)
}

// NewRepository creates an Actor from a Repository ID.
func NewRepository(repositoryID string) vexi.Actor {
	return newConcreteActor("Repository", repositoryID)
}

// NewOAuthApplication creates an Actor from a OAuthApplication ID.
func NewOAuthApplication(oauthApplicationID string) vexi.Actor {
	return newConcreteActor("OauthApplication", oauthApplicationID)
}

// NewGitHubApp creates an Actor from a GitHub App Integration ID.
func NewGitHubApp(integrationID string) vexi.Actor {
	return newConcreteActor("Integration", integrationID)
}

// NewSecurityAdvisory creates an Actor from a Vulnerability ID.
func NewSecurityAdvisory(securityAdvistoryID string) vexi.Actor {
	return newConcreteActor("Vulnerability", securityAdvistoryID)
}

// NewMemexProject creates an Actor from a Memex Project ID.
func NewMemexProject(memexProjectID string) vexi.Actor {
	return newConcreteActor("MemexProject", memexProjectID)
}

// NewHost creates an Actor from a Host name.
func NewHost(hostName string) vexi.Actor {
	return newConcreteActor("GitHub::FlipperHost", hostName)
}

// NewSite creates an Actor from a Site name.
func NewSite(siteName string) vexi.Actor {
	return newConcreteActor("GitHub::FlipperSite", siteName)
}

// NewRole creates an Actor from a Role name.
func NewRole(roleName string) vexi.Actor {
	return newConcreteActor("GitHub::FlipperRole", roleName)
}

// NewCustomActorType creates an Actor from a type and an identifier.
func NewCustomActorType(actorType, id string) vexi.Actor {
	return newConcreteActor(actorType, id)
}

// Int64 returns the int64 representation of the actor ID, if applicable.
func (a *concreteActor) Int64() (int64, error) {
	return strconv.ParseInt(a.actorID, 10, 64)
}

// String returns the string representation of the actor ID.
func (a *concreteActor) String() string {
	return a.actorID
}
