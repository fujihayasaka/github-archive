package models

import (
	"time"

	"gopkg.in/guregu/null.v4"
)

// OrganizationCredentialAuthorization contains information about whether the token is allowed to access SSO-required
// resources for a particular organization
type OrganizationCredentialAuthorization struct {
	ID             int64             `db:"id" json:"id"`
	OrganizationID int64             `db:"organization_id" json:"organization_id"`
	CredentialID   int64             `db:"credential_id" json:"credential_id"`
	CredentialType string            `db:"credential_type" json:"credential_type"`
	CreatedAt      NullMysqlDateTime `db:"created_at" json:"created_at"`
	RevokedAt      NullMysqlDateTime `db:"revoked_at" json:"revoked_at"`
	RevokedById    null.Int          `db:"revoked_by_id" json:"revoked_by_id"`
}

// IsRevoked returns true if the sso was revoked and the timestamp is
// before now
func (os *OrganizationCredentialAuthorization) IsRevoked() bool {
	return os.RevokedAt.Valid && os.RevokedAt.Time.Before(time.Now())
}
