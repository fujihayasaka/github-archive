package testfixtures

import (
	"time"

	"github.com/github/authnd/internal/common/models"
)

var ScopedIntegrationInstallations = []*models.ScopedIntegrationInstallation{
	DefaultScopedIntegrationInstallation,
}

var DefaultScopedIntegrationInstallation = &models.ScopedIntegrationInstallation{
	ID:                        1,
	IntegrationInstallationID: DefaultIntegrationInstallation.ID,
	CreatedAt:                 time.Now().Add(-1 * time.Hour).UTC(),
	UpdatedAt:                 time.Now().Add(-1 * time.Hour).UTC(),
}
