package models

import "time"

type ScopedIntegrationInstallation struct {
	ID                        uint64    `db:"id" json:"id"`
	IntegrationInstallationID uint64    `db:"integration_installation_id" json:"integration_installation_id"`
	CreatedAt                 time.Time `db:"created_at" json:"created_at"`
	UpdatedAt                 time.Time `db:"updated_at" json:"updated_at"`
	ExpiresAt                 *int64    `db:"expires_at" json:"expires_at"`
}

func (i *ScopedIntegrationInstallation) IsExpired(now time.Time) bool {
	if i.ExpiresAt == nil {
		return false
	}

	return now.After(time.Unix(*i.ExpiresAt, 0))
}
