package models

import (
	"gopkg.in/guregu/null.v4"
)

// OAuthApplication is the model for the oauth_accesses table.
type OAuthApplication struct {
	ID        int64             `db:"id" json:"id"`
	Name      null.String       `db:"name" json:"name"`
	Key       null.String       `db:"key" json:"key"`
	UserID    null.Int          `db:"user_id" json:"user_id"`
	CreatedAt NullMysqlDateTime `db:"created_at" json:"created_at"`
	State     int               `db:"state" json:"state"`
}
