package models

import "time"

type AuthenticationToken struct {
	ID                  uint64    `db:"id"`
	AuthenticatableID   uint64    `db:"authenticatable_id"`
	AuthenticatableType string    `db:"authenticatable_type"`
	HashedValue         string    `db:"hashed_value"`
	CreatedAt           time.Time `db:"created_at"`
	UpdatedAt           time.Time `db:"updated_at"`
	// because `expires_at_timestamp` is stored as a nullable bigint, it can't be
	// unmarshalled automatically into a *time.Time or NullMySQLDateTime
	ExpiresAt *int64 `db:"expires_at_timestamp"`
}

func (t *AuthenticationToken) IsExpired(now time.Time) bool {
	if t.ExpiresAt == nil {
		return false
	}

	return now.After(time.Unix(*t.ExpiresAt, 0))
}
