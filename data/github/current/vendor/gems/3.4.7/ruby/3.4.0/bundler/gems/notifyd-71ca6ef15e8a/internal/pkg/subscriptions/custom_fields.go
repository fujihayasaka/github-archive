package subscriptions

import (
	"github.com/github/notifyd/internal/pkg/mysql"
)

// CustomField contains the internal data model for custom fields.
type CustomField struct {
	Name  string `json:"name"`
	Value string `json:"value"`
}

// sqlCustomField contains the SQL data model for custom fields.
type sqlCustomField struct {
	ID             int64  `db:"id"      json:"-"`
	UserID         int64  `db:"user_id" json:"-"`
	SubscriptionID int64  `db:"meta_id" json:"-"`
	Name           string `db:"name"    json:"name"`
	Value          string `db:"value"   json:"value"`
	mysql.Timestamps
}
