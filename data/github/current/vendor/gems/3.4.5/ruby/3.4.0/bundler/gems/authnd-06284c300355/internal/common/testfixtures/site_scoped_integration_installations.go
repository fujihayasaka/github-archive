package testfixtures

import (
	"time"

	"github.com/github/authnd/internal/common/models"
)

var SiteScopedIntegrationInstallations = []*models.SiteScopedIntegrationInstallation{
	DefaultSiteScopedIntegrationInstallation,
}

var DefaultSiteScopedIntegrationInstallation = &models.SiteScopedIntegrationInstallation{
	ID:                 1,
	IntegrationID:      DefaultIntegration.ID,
	TargetID:           uint64(MonalisaUser.ID),
	AbstractTargetType: "User",
	CreatedAt:          time.Now().Add(-1 * time.Hour).UTC(),
	UpdatedAt:          time.Now().Add(-1 * time.Hour).UTC(),
}
