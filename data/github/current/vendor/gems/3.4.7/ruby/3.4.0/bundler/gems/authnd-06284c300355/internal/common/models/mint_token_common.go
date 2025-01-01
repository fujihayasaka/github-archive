package models

import "time"

type MintTokenCommon struct {
	ID         uint64            `db:"id"`
	ActorID    uint64            `db:"actor_id"`
	ActorType  string            `db:"actor_type"`
	IssuedAt   time.Time         `db:"issued_at_utc"`
	ExpiresAt  NullMysqlDateTime `db:"expires_at_utc"`
	RevokedAt  NullMysqlDateTime `db:"revoked_at_utc"`
	Attributes []byte            `db:"attributes"`
}

// IsExpired returns true if token expiry is set and before or equal current time (UTC)
func (tk *MintTokenCommon) IsExpired(currentTimeUTC time.Time) bool {
	return tk.ExpiresAt.Valid && !tk.ExpiresAt.Time.After(currentTimeUTC)
}

// IsRevoked returns true if revoked date is set
func (tk *MintTokenCommon) IsRevoked() bool {
	return tk.RevokedAt.Valid
}
