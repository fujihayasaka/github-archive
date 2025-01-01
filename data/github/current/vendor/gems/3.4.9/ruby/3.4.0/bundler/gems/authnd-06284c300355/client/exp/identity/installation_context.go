package identity

import "fmt"

type InstallationType string

const (
	InstallationTypeIntegrationInstallation           InstallationType = "IntegrationInstallation"
	InstallationTypeScopedIntegrationInstallation     InstallationType = "ScopedIntegrationInstallation"
	InstallationTypeSiteScopedIntegrationInstallation InstallationType = "SiteScopedIntegrationInstallation"
)

type InstallationContext struct {
	InstallationID       *uint64
	ScopedInstallationID *uint64

	InstallationType InstallationType

	InstallationTargetID   uint64
	InstallationTargetType InstallationTargetType
}

func (i *InstallationContext) IsIntegrationInstallation() bool {
	return i.InstallationType == InstallationTypeIntegrationInstallation
}

func (i *InstallationContext) IsScopedIntegrationInstallation() bool {
	return i.InstallationType == InstallationTypeScopedIntegrationInstallation
}

func (i *InstallationContext) IsSiteScopedIntegrationInstallation() bool {
	return i.InstallationType == InstallationTypeSiteScopedIntegrationInstallation
}

func (i *InstallationContext) isValid() bool {
	if i.InstallationTargetType != InstallationTargetTypeUser && i.InstallationTargetType != InstallationTargetTypeOrganization && i.InstallationTargetType != InstallationTargetTypeBusiness {
		return false
	}

	// IntegrationInstallation and ScopedIntegrationInstallation must have an installation ID
	if (i.IsIntegrationInstallation() || i.IsScopedIntegrationInstallation()) && i.InstallationID == nil {
		return false
	}

	// ScopedIntegrationInstallation and SiteScopedIntegrationInstallation must have a scoped installation ID
	if (i.IsScopedIntegrationInstallation() || i.IsSiteScopedIntegrationInstallation()) && i.ScopedInstallationID == nil {
		return false
	}

	return true
}

type InstallationTargetType string

const (
	// InstallationTargetTypeUser is the installation target type for a user
	// Note that it is _not_ to be used as a representation of the underlying table like the monolith does
	// i.e. "User" means it is owned by a legitimate user, never an Organization.
	InstallationTargetTypeUser InstallationTargetType = "User"

	// InstallationTargetTypeOrganization is the installation target type for an organization
	InstallationTargetTypeOrganization InstallationTargetType = "Organization"

	// InstallationTargetTypeBusiness is the installation target type for a business
	InstallationTargetTypeBusiness InstallationTargetType = "Business"
)

func ParseInstallationTargetType(installationTargetType string) (InstallationTargetType, error) {
	switch installationTargetType {
	case string(InstallationTargetTypeUser):
		return InstallationTargetTypeUser, nil
	case string(InstallationTargetTypeOrganization):
		return InstallationTargetTypeOrganization, nil
	case string(InstallationTargetTypeBusiness):
		return InstallationTargetTypeBusiness, nil
	default:
		return "", fmt.Errorf("invalid installation target type: %s", installationTargetType)
	}
}

func NewIntegrationInstallation(installationID uint64, installationTargetID uint64, installationTargetType InstallationTargetType) *InstallationContext {
	return &InstallationContext{
		InstallationID:         &installationID,
		InstallationType:       InstallationTypeIntegrationInstallation,
		InstallationTargetID:   installationTargetID,
		InstallationTargetType: installationTargetType,
	}
}

func NewScopedIntegrationInstallation(installationID uint64, scopedInstallationID uint64, installationTargetID uint64, installationTargetType InstallationTargetType) *InstallationContext {
	return &InstallationContext{
		InstallationID:         &installationID,
		ScopedInstallationID:   &scopedInstallationID,
		InstallationType:       InstallationTypeScopedIntegrationInstallation,
		InstallationTargetID:   installationTargetID,
		InstallationTargetType: installationTargetType,
	}
}

func NewSiteScopedIntegrationInstallation(scopedInstallationID uint64, installationTargetID uint64, installationTargetType InstallationTargetType) *InstallationContext {
	return &InstallationContext{
		ScopedInstallationID:   &scopedInstallationID,
		InstallationType:       InstallationTypeSiteScopedIntegrationInstallation,
		InstallationTargetID:   installationTargetID,
		InstallationTargetType: installationTargetType,
	}
}
