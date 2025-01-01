package models

import (
	"time"

	"github.com/github/authnd/client"
	"github.com/github/authnd/internal/common/zson"
	"github.com/pkg/errors"
	"gopkg.in/guregu/null.v4"
)

const (
	appTypeOauthApplication = "OauthApplication"
	appTypeIntegration      = "Integration"
)

// OAuthAccess is the model for the oauth_accesses table.
type OAuthAccess struct {
	ID               int64             `db:"id" json:"id"`
	UserID           int64             `db:"user_id" json:"user_id"`
	ApplicationID    int64             `db:"application_id" json:"application_id"`
	Code             null.String       `db:"code" json:"code"`
	RawData          []byte            `db:"raw_data" json:"raw_data"`
	CreatedAt        NullMysqlDateTime `db:"created_at" json:"created_at"`
	Description      null.String       `db:"description" json:"description"`
	AccessedAt       NullMysqlDateTime `db:"accessed_at" json:"accessed_at"`
	HashedToken      []byte            `db:"hashed_token" json:"hashed_token"`
	TokenLastEight   null.String       `db:"token_last_eight" json:"token_last_eight"`
	Fingerprint      null.String       `db:"fingerprint" json:"fingerprint"`
	AuthorizationID  null.Int          `db:"authorization_id" json:"authorization_id"`
	ApplicationType  null.String       `db:"application_type" json:"application_type"`
	ExpiresAt        null.Int          `db:"expires_at_timestamp" json:"expires_at_timestamp"` // bigint(20) timestamps need to be represented as int rather than a date
	InstallationID   null.Int          `db:"installation_id" json:"installation_id"`
	InstallationType null.String       `db:"installation_type" json:"installation_type"`
	IsApplication    null.Bool         `db:"is_application" json:"-"`
	LastIssuedAt     NullMysqlDateTime `db:"last_issued_at" json:"last_issued_at"`
}

// IsExpired returns true if the sso was revoked and the timestamp is
// before now
func (oa *OAuthAccess) IsExpired(currentTime time.Time) bool {
	return oa.ExpiresAt.Valid && oa.ExpiresAt.Int64 <= currentTime.Unix()
}

// GetCredentialType returns the oauth accesses credential type
func (oa *OAuthAccess) GetCredentialType() (string, error) {
	switch oa.ApplicationID {
	case 0:
		return "PersonalAccessToken", nil
	default:
		if !oa.ApplicationType.Valid {
			return "", errors.New("application_type is null for this oauth_access")
		}

		if oa.ApplicationType.String == appTypeOauthApplication {
			return "OAuthApplicationToken", nil
		} else if oa.ApplicationType.String == appTypeIntegration {
			return string(client.CredentialTypeUserToServerToken), nil
		} else {
			return "", errors.Errorf("unexpected ApplicationType '%s'", oa.ApplicationType.String)
		}
	}
}

// OAuthAccessData holds data parsed from the `RawData` field of an OAuthAccess.
type OAuthAccessData struct {
	Scopes []string `json:"scopes"`

	// See app/models/coders/oauth_access_coder in github/github for all the fields expected on this ZSON object.
}

// ReadRawData reads the RawData value in an OAuthAccess and returns a parsed representation of it.
func (oa *OAuthAccess) ReadRawData() (OAuthAccessData, error) {
	var data OAuthAccessData

	if len(oa.RawData) > 0 {
		err := zson.Unmarshal(oa.RawData, &data)
		return data, err
	}

	// If raw data is empty, just return an empty object.
	return data, nil
}

type ApplicationContext struct {
	ApplicationKey         null.String `db:"application_key"`
	ApplicationOwnerID     null.Int    `db:"application_owner_id"`
	ApplicationOwnerType   null.String `db:"application_owner_type"`
	ApplicationOwnerSpammy null.Int    `db:"application_owner_spammy"`
	ApplicationSuspended   null.Bool   `db:"application_suspended"`
}

// OAuthAccessWithTokenContext holds parts of the OAuthAccesses model including owner information required for OAuth Access token validation
type OAuthAccessWithTokenContext struct {
	OAuthAccess
	ApplicationContext
}

// IsApplicationAndSuspended returns true if the oauth access is linked to a suspended application/integration
func (oa *OAuthAccessWithTokenContext) IsApplicationAndSuspended() bool {
	if oa.HasApplication() && oa.ApplicationSuspended.Valid {
		return oa.ApplicationSuspended.Bool
	}
	return false
}

// IsApplicationOwnerSpammy returns true if the OAuth application owner is spammy
func (oa *OAuthAccessWithTokenContext) IsApplicationOwnerSpammy() bool {
	if oa.HasApplication() && oa.ApplicationOwnerSpammy.Valid {
		return oa.ApplicationOwnerSpammy.Int64 == 1
	}
	return false
}

func (oa *OAuthAccessWithTokenContext) isOAuthApplication() bool {
	return oa.ApplicationID > 0 && oa.ApplicationType.Valid && oa.ApplicationType.String == appTypeOauthApplication
}

func (oa *OAuthAccessWithTokenContext) isIntegration() bool {
	return oa.ApplicationID > 0 && oa.ApplicationType.Valid && oa.ApplicationType.String == appTypeIntegration
}

func (oa *OAuthAccessWithTokenContext) HasApplication() bool {
	return oa.isIntegration() || oa.isOAuthApplication()
}

func (oa *OAuthAccessWithTokenContext) HasValidApplicationOwner() bool {
	return oa.ApplicationOwnerID.Valid && oa.ApplicationOwnerType.Valid
}
