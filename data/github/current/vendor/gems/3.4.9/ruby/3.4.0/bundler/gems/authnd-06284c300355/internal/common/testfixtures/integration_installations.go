package testfixtures

import (
	"github.com/github/authnd/internal/common/models"
	"gopkg.in/guregu/null.v4"
)

var IntegrationInstallations = []*models.IntegrationInstallation{
	DefaultIntegrationInstallation,
	SuspendedIntegrationInstallation,
	SpammyUserIntegrationInstallation,
	SuspendedBotIntegrationInstallation,
	UserSuspendedIntegrationInstallation,
	IntegratorSuspendedIntegrationInstallation,
	IntegrationInstallationOnOrganizationAndOwnedByOrg,
}

var DefaultIntegrationInstallation = &models.IntegrationInstallation{
	ID:                 1,
	IntegrationID:      DefaultIntegration.ID,
	TargetID:           uint64(MonalisaUser.ID),
	AbstractTargetType: "User",
}

var SuspendedIntegrationInstallation = &models.IntegrationInstallation{
	ID:                 2,
	IntegrationID:      SuspendedIntegration.ID,
	TargetID:           uint64(MonalisaUser.ID),
	AbstractTargetType: "User",
}

var SpammyUserIntegrationInstallation = &models.IntegrationInstallation{
	ID:                 3,
	IntegrationID:      SpammyUserIntegration.ID,
	TargetID:           uint64(MonalisaUser.ID),
	AbstractTargetType: "User",
}

var SuspendedBotIntegrationInstallation = &models.IntegrationInstallation{
	ID:                 4,
	IntegrationID:      SuspendedBotIntegration.ID,
	TargetID:           uint64(MonalisaUser.ID),
	AbstractTargetType: "User",
}

var UserSuspendedIntegrationInstallation = &models.IntegrationInstallation{
	ID:                 5,
	IntegrationID:      DefaultIntegration.ID,
	UserSuspendedByID:  null.IntFrom(MonalisaUser.ID),
	TargetID:           uint64(MonalisaUser.ID),
	AbstractTargetType: "User",
}

var IntegratorSuspendedIntegrationInstallation = &models.IntegrationInstallation{
	ID:                  6,
	IntegrationID:       DefaultIntegration.ID,
	IntegratorSuspended: true,
	TargetID:            uint64(MonalisaUser.ID),
	AbstractTargetType:  "User",
}

var IntegrationInstallationOnOrganizationAndOwnedByOrg = &models.IntegrationInstallation{
	ID:                 7,
	IntegrationID:      IntegrationOwnedByOrg.ID,
	TargetID:           uint64(OrgOne.ID),
	AbstractTargetType: "User", // this is what's stored in the DB
}
