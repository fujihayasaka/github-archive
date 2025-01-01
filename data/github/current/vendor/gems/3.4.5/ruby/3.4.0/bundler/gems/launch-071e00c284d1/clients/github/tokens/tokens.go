package tokens

import (
	"time"
)

// AccessToken represents any type of access token for GitHub API requests.
type AccessToken struct {
	Expiry      time.Time               `json:"expiry"`
	Token       string                  `json:"token"`
	Permissions InstallationPermissions `json:"perms"`
	ValidAfter  *time.Time              `json:"valid_after"`
}

// String returns the string form of the access token.
func (a AccessToken) String() string {
	return a.Token
}

type TokenPermissionSet string

const LimitedReadPermissions TokenPermissionSet = "LimitedReadPermissions"
const ReadPermissions TokenPermissionSet = "ReadPermissions"
const WritePermissions TokenPermissionSet = "WritePermissions"

// NewInstallationPermissions creates a new set of InstallationPermissions with RO or RW access
func NewInstallationPermissions(permissionSet TokenPermissionSet) *InstallationPermissions {
	var safeAccessLevel, safeContentsAccessLevel, safePackagesAccessLevel InstallationPermissionAccess
	switch permissionSet {
	case ReadPermissions:
		safeAccessLevel = ReadAccess
		safeContentsAccessLevel = ReadAccess
		safePackagesAccessLevel = ReadAccess
	case WritePermissions:
		safeAccessLevel = WriteAccess
		safeContentsAccessLevel = WriteAccess
		safePackagesAccessLevel = WriteAccess
	case LimitedReadPermissions:
		// In case of default readonly permissions, we need to set the contents and packages access level to read
		safeAccessLevel = NoneAccess
		safeContentsAccessLevel = ReadAccess
		safePackagesAccessLevel = ReadAccess
	default:
		safeAccessLevel = NoneAccess
		safeContentsAccessLevel = NoneAccess
		safePackagesAccessLevel = NoneAccess
	}

	// See https://thehub.github.com/epd/engineering/products-and-services/actions/updating-actions-app/#updating-permissions for additional
	// required steps when updating permissions.
	return &InstallationPermissions{
		Actions:            safeAccessLevel,
		Attestations:       safeAccessLevel,
		Checks:             safeAccessLevel,
		Contents:           safeContentsAccessLevel,
		Deployments:        safeAccessLevel,
		Issues:             safeAccessLevel,
		Discussions:        safeAccessLevel,
		Metadata:           ReadAccess,
		Packages:           safePackagesAccessLevel,
		Pages:              safeAccessLevel,
		PullRequests:       safeAccessLevel,
		RepositoryProjects: safeAccessLevel,
		Statuses:           safeAccessLevel,
		SecurityEvents:     safeAccessLevel,
	}
}

// ServiceToken represents a GraphQL service token
type ServiceToken string

// NullServiceToken is a empty initialized token for equality checks
var NullServiceToken ServiceToken

// String returns the string form of the service token.
func (s ServiceToken) String() string {
	return string(s)
}
