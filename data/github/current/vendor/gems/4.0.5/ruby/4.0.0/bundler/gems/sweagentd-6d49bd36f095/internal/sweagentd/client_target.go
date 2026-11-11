package sweagentd

import "fmt"

// ClientTargetType represents the type of rate limiting target.
type ClientTargetType int

const (
	// ClientTargetTypeApp represents the GitHub ClientTargetTypeApp itself (for JWT authenticated requests).
	ClientTargetTypeApp ClientTargetType = iota

	// ClientTargetTypeInstallation represents an installation target, such as the owner of a repository.
	ClientTargetTypeInstallation

	// ClientTargetTypeUser represents a user target, such as an actor initiating jobs.
	ClientTargetTypeUser
)

func (tt ClientTargetType) name() string {
	switch tt {
	case ClientTargetTypeApp:
		return "app"

	case ClientTargetTypeInstallation:
		return "installation"

	case ClientTargetTypeUser:
		return "user"

	default:
		return "unknown"
	}
}

// ClientTarget represents a rate limiting target, which can be either an installation
// or a user, identified by their respective IDs. This is also used as a key for token
// caching in the tokens package.
type ClientTarget struct {
	// App is the GitHub App ID associated with the target.
	App int64

	// Type is the type of the target (Installation or User).
	Type ClientTargetType

	// ID is the ID of the target (installation/owner ID or user ID).
	ID int64

	// Name is an optional name (login/slug) of the target when ID is not available.
	// IMPORTANT: This should only be used when the target ID is not available.
	Name string
}

// newClientTarget creates a new Target with the given app, target type, and target ID.
func newClientTarget(app int64, targetType ClientTargetType, id int64) ClientTarget {
	return ClientTarget{
		App:  app,
		Type: targetType,
		ID:   id,
	}
}

// newClientTargetWithName creates a new Target with the given app, target type,
// and target name.
//
// IMPORTANT: This should only be used when the target ID is not available.
func newClientTargetWithName(app int64, targetType ClientTargetType, name string) ClientTarget {
	return ClientTarget{
		App:  app,
		Type: targetType,
		Name: name,
	}
}

// Key returns the string key representation of the Target in the format:
// "app:{app}:type:{type}:id:{id}" or "app:{app}:type:{type}:name:{name}".
func (t ClientTarget) Key() string {
	if t.ID == 0 && t.Name != "" {
		return fmt.Sprintf("app:%d:type:%s:name:%s", t.App, t.Type.name(), t.Name)
	}

	return fmt.Sprintf("app:%d:type:%s:id:%d", t.App, t.Type.name(), t.ID)
}

// ClientTargetForUser creates a ClientTarget for a user with the given app ID and user ID.
func ClientTargetForUser(appID, userID int64) ClientTarget {
	return newClientTarget(appID, ClientTargetTypeUser, userID)
}

// ClientTargetForApp creates a ClientTarget for the app itself with the given app ID.
func ClientTargetForApp(appID int64) ClientTarget {
	return newClientTarget(appID, ClientTargetTypeApp, appID)
}

// ClientTargetForInstallationByOwnerID creates a ClientTarget for an installation
// with the given app ID and owner ID.
func ClientTargetForInstallationByOwnerID(appID, ownerID int64) ClientTarget {
	return newClientTarget(appID, ClientTargetTypeInstallation, ownerID)
}

// ClientTargetForInstallationByOwnerName creates a ClientTarget for an installation
// with the given app ID and owner name.
//
// IMPORTANT: This should only be used when the owner ID is not available.
func ClientTargetForInstallationByOwnerName(appID int64, ownerName string) ClientTarget {
	return newClientTargetWithName(appID, ClientTargetTypeInstallation, ownerName)
}
