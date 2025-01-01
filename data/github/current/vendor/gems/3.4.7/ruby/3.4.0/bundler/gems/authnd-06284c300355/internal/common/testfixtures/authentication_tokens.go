package testfixtures

import (
	"time"

	"github.com/github/authnd/internal/common/models"
	"github.com/github/authnd/internal/common/tokens"
)

const (
	// generated with Rails console in Dotcom codespace:
	//	 AuthenticationToken.generate_random_token_pair.first
	UnscopedAuthenticationTokenValue                        = "ghs_yluBtAeLFkzhyXd2oByHyFy96ST3vX1S3aIj"
	UnscopedAuthenticationTokenValueForOrgInstallation      = "ghs_xluBtAeLFkzhyXd2oByHyFy96ST3vX1S3aIj"
	ScopedAuthenticationTokenValue                          = "ghs_hbhFI4XWdB6iL1XcxYV8A4pDLlOg9z1eXSQZ"
	SiteScopedAuthenticationTokenValue                      = "ghs_82ejQiujh0JbwMnhm7OBRJvdEngzV73zNP77"
	ExpiredAuthenticationTokenValue                         = "ghs_eUedzz9D5nXYjzlk1FV8zm5AAuaXM42MBGKH"
	SuspendIntegrationAuthenticationTokenValue              = "ghs_zboLaGIqdHTKoaYW9DqepdaLku5Cw43Gwx6q"
	SpammyUserAuthenticationTokenValue                      = "ghs_bGULvxcFpPei0PD0XA154Cz1WxlHp82fYLG5"
	SuspendedBotAuthenticationTokenValue                    = "ghs_Eg6MlIO2RpAdAggwredkatzRwLqmaI0y3ud0"
	InstallationUserSuspendedAuthenticationTokenValue       = "ghs_utPz3HbCMeG3VphZP5fbvOrZotPdJr1EiY8L"
	InstallationIntegratorSuspendedAuthenticationTokenValue = "ghs_p19EHUdosy71pC7v8EnsFVLDhQFmbP20Pw2C"
)

var AuthenticationTokens = []*models.AuthenticationToken{
	UnscopedAuthenticationToken,
	ScopedAuthenticationToken,
	SiteScopedAuthenticationToken,
	ExpiredAuthenticationToken,
	SuspendIntegrationAuthenticationToken,
	SpammyUserIntegrationAuthenticationToken,
	SuspendedBotAuthenticationToken,
	InstallationUserSuspendedAuthenticationToken,
	InstallationIntegratorSuspendedAuthenticationToken,
	UnscopedAuthenticationTokenOwnedByOrgAndInstalledOnOrg,
}

var UnscopedAuthenticationToken = &models.AuthenticationToken{
	ID:                  1,
	AuthenticatableID:   DefaultIntegrationInstallation.ID,
	AuthenticatableType: "IntegrationInstallation",
	HashedValue:         tokens.Hash(UnscopedAuthenticationTokenValue),
	CreatedAt:           time.Now().Add(-1 * time.Hour).UTC(),
	UpdatedAt:           time.Now().Add(-1 * time.Hour).UTC(),
}

var UnscopedAuthenticationTokenOwnedByOrgAndInstalledOnOrg = &models.AuthenticationToken{
	ID:                  2,
	AuthenticatableID:   IntegrationInstallationOnOrganizationAndOwnedByOrg.ID,
	AuthenticatableType: "IntegrationInstallation",
	HashedValue:         tokens.Hash(UnscopedAuthenticationTokenValueForOrgInstallation),
	CreatedAt:           time.Now().Add(-1 * time.Hour).UTC(),
	UpdatedAt:           time.Now().Add(-1 * time.Hour).UTC(),
}

var ScopedAuthenticationToken = &models.AuthenticationToken{
	ID:                  3,
	AuthenticatableID:   DefaultScopedIntegrationInstallation.ID,
	AuthenticatableType: "ScopedIntegrationInstallation",
	HashedValue:         tokens.Hash(ScopedAuthenticationTokenValue),
	CreatedAt:           time.Now().Add(-1 * time.Hour).UTC(),
	UpdatedAt:           time.Now().Add(-1 * time.Hour).UTC(),
}

var SiteScopedAuthenticationToken = &models.AuthenticationToken{
	ID:                  4,
	AuthenticatableID:   DefaultSiteScopedIntegrationInstallation.ID,
	AuthenticatableType: "SiteScopedIntegrationInstallation",
	HashedValue:         tokens.Hash(SiteScopedAuthenticationTokenValue),
	CreatedAt:           time.Now().Add(-1 * time.Hour).UTC(),
	UpdatedAt:           time.Now().Add(-1 * time.Hour).UTC(),
}

var ExpiredAuthenticationToken = &models.AuthenticationToken{
	ID:                  5,
	AuthenticatableID:   DefaultIntegrationInstallation.ID,
	AuthenticatableType: "IntegrationInstallation",
	HashedValue:         tokens.Hash(ExpiredAuthenticationTokenValue),
	CreatedAt:           time.Now().Add(-1 * time.Hour).UTC(),
	UpdatedAt:           time.Now().Add(-1 * time.Hour).UTC(),
	ExpiresAt:           intPtr(time.Now().Add(-30 * time.Minute).UTC().Unix()),
}

var SuspendIntegrationAuthenticationToken = &models.AuthenticationToken{
	ID:                  6,
	AuthenticatableID:   SuspendedIntegrationInstallation.ID,
	AuthenticatableType: "IntegrationInstallation",
	HashedValue:         tokens.Hash(SuspendIntegrationAuthenticationTokenValue),
	CreatedAt:           time.Now().Add(-1 * time.Hour).UTC(),
	UpdatedAt:           time.Now().Add(-1 * time.Hour).UTC(),
}

var SpammyUserIntegrationAuthenticationToken = &models.AuthenticationToken{
	ID:                  7,
	AuthenticatableID:   SpammyUserIntegrationInstallation.ID,
	AuthenticatableType: "IntegrationInstallation",
	HashedValue:         tokens.Hash(SpammyUserAuthenticationTokenValue),
	CreatedAt:           time.Now().Add(-1 * time.Hour).UTC(),
	UpdatedAt:           time.Now().Add(-1 * time.Hour).UTC(),
}

var SuspendedBotAuthenticationToken = &models.AuthenticationToken{
	ID:                  8,
	AuthenticatableID:   SuspendedBotIntegrationInstallation.ID,
	AuthenticatableType: "IntegrationInstallation",
	HashedValue:         tokens.Hash(SuspendedBotAuthenticationTokenValue),
	CreatedAt:           time.Now().Add(-1 * time.Hour).UTC(),
	UpdatedAt:           time.Now().Add(-1 * time.Hour).UTC(),
}

var InstallationUserSuspendedAuthenticationToken = &models.AuthenticationToken{
	ID:                  9,
	AuthenticatableID:   UserSuspendedIntegrationInstallation.ID,
	AuthenticatableType: "IntegrationInstallation",
	HashedValue:         tokens.Hash(InstallationUserSuspendedAuthenticationTokenValue),
	CreatedAt:           time.Now().Add(-1 * time.Hour).UTC(),
	UpdatedAt:           time.Now().Add(-1 * time.Hour).UTC(),
}

var InstallationIntegratorSuspendedAuthenticationToken = &models.AuthenticationToken{
	ID:                  10,
	AuthenticatableID:   IntegratorSuspendedIntegrationInstallation.ID,
	AuthenticatableType: "IntegrationInstallation",
	HashedValue:         tokens.Hash(InstallationIntegratorSuspendedAuthenticationTokenValue),
	CreatedAt:           time.Now().Add(-1 * time.Hour).UTC(),
	UpdatedAt:           time.Now().Add(-1 * time.Hour).UTC(),
}

func intPtr(i int64) *int64 {
	return &i
}
