package models

import "gopkg.in/guregu/null.v4"

type IntegrationInstallation struct {
	ID            uint64 `db:"id" json:"id"`
	IntegrationID uint64 `db:"integration_id"`

	TargetID uint64 `db:"target_id"`
	// target_type is either "User" or "Business"
	// be careful when using this field, since "User" can be either a user or an organization
	AbstractTargetType string `db:"target_type"`

	UserSuspendedByID   null.Int `db:"user_suspended_by_id"`
	IntegratorSuspended bool     `db:"integrator_suspended"`
}

func (i *IntegrationInstallation) IsSuspended() bool {
	return i.UserSuspendedByID.Valid || i.IntegratorSuspended
}

// `target_type` in the DB is either "User" or "Business"
// `precise_target_type` maps "User" to the underlying users table type ("User" or "Organization")
type IntegrationInstallationWithPreciseTargetType struct {
	IntegrationInstallation
	PreciseTargetType string `db:"precise_target_type"`
}
