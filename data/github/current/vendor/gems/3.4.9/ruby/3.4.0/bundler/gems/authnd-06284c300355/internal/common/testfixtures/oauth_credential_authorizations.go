package testfixtures

import (
	"time"

	"github.com/github/authnd/internal/common/models"
)

var PublicKeyOrganizationSSOs = map[int64][]models.OrganizationCredentialAuthorization{
	MonalisaPublicKey.ID: {MonalisaPublicKeySSOAuthorization, MonalisaRevokedPublicKeySSOAuthorization},
}

var OAuthOrganizationSSOs = map[int64][]models.OrganizationCredentialAuthorization{
	MonalisaOAuthAccess.ID: {MonalisaOAuthSSOAuthorization, MonalisaRevokedOAuthSSOAuthorization},
}

var MonalisaPublicKeySSOAuthorization = models.OrganizationCredentialAuthorization{
	OrganizationID: 15,
	CredentialID:   MonalisaPublicKey.ID,
	CredentialType: "PublicKey",
}

var MonalisaRevokedPublicKeySSOAuthorization = models.OrganizationCredentialAuthorization{
	OrganizationID: 18,
	CredentialID:   MonalisaPublicKey.ID,
	CredentialType: "PublicKey",
	RevokedAt:      models.NullMysqlDateTimeFromTime(time.Date(2000, 1, 11, 10, 1, 2, 0, time.UTC)),
}

var MonalisaOAuthSSOAuthorization = models.OrganizationCredentialAuthorization{
	ID:             1,
	OrganizationID: 24,
	CredentialID:   MonalisaOAuthAccess.ID,
	CredentialType: "OauthAccess",
}

var MonalisaRevokedOAuthSSOAuthorization = models.OrganizationCredentialAuthorization{
	ID:             2,
	OrganizationID: 26,
	CredentialID:   MonalisaOAuthAccess.ID,
	CredentialType: "OauthAccess",
	RevokedAt:      models.NullMysqlDateTimeFromTime(time.Date(2000, 1, 11, 10, 1, 2, 0, time.UTC)),
}
