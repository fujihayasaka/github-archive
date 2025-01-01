package models

import "time"

type SiteScopedIntegrationInstallation struct {
	ID            uint64 `db:"id" json:"id"`
	IntegrationID uint64 `db:"integration_id" json:"integration_id"`

	TargetID uint64 `db:"target_id"`
	// target_type is either "User" or "Business"
	// be careful when using this field, since "User" can be either a user or an organization
	AbstractTargetType string `db:"target_type"`

	CreatedAt time.Time `db:"created_at" json:"created_at"`
	UpdatedAt time.Time `db:"updated_at" json:"updated_at"`
	ExpiresAt *int64    `db:"expires_at" json:"expires_at"`
}

func (i *SiteScopedIntegrationInstallation) IsExpired(now time.Time) bool {
	if i.ExpiresAt == nil {
		return false
	}

	return now.After(time.Unix(*i.ExpiresAt, 0))
}

// `target_type` in the DB is either "User" or "Business"
// `precise_target_type` maps "User" to the underlying users table type ("User" or "Organization")
type SiteScopedIntegrationInstallationWithPreciseTargetType struct {
	SiteScopedIntegrationInstallation
	PreciseTargetType string `db:"precise_target_type"`
}
