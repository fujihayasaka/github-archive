package models

import (
	"gopkg.in/guregu/null.v4"
)

type integrationState int

const (
	integrationStateActive integrationState = iota
	integrationStateSuspended
)

// Integration is the model for the integrations table.
type Integration struct {
	ID uint64 `db:"id" json:"id"`

	OwnerID uint64 `db:"owner_id" json:"owner_id"`
	// owner_type is either "User" or "Business"
	// be careful when using this field, since "User" can be either a user or an organization
	AbstractOwnerType string `db:"owner_type" json:"owner_type"`

	BotID      uint64            `db:"bot_id" json:"bot_id"`
	Name       null.String       `db:"name" json:"name"`
	Key        null.String       `db:"key" json:"key"`
	CreatedAt  NullMysqlDateTime `db:"created_at" json:"created_at"`
	State      int               `db:"state" json:"state"`
	UserHidden bool              `db:"user_hidden" json:"user_hidden"`
}

func (i *Integration) IsSuspended() bool {
	return i.State == int(integrationStateSuspended)
}

func (i *Integration) UserSpammy() bool {
	return i.UserHidden
}

// `owner_type` in the DB is either "User" or "Business"
// `precise_owner_type` maps "User" to the underlying users table type ("User" or "Organization")
type IntegrationWithPreciseOwner struct {
	Integration
	PreciseOwnerType string `db:"precise_owner_type" json:"precise_owner_type"`
}
