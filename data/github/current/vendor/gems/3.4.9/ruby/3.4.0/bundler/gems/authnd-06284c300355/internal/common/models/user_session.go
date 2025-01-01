package models

import (
	"time"

	"gopkg.in/guregu/null.v4"
)

var (
	Week time.Duration = time.Hour * 24 * 7
)

type UserSession struct {
	ID                    int64             `db:"id" json:"id"`
	UserID                int64             `db:"user_id" json:"user_id"`
	IP                    null.String       `db:"ip" json:"ip"`
	TimeZoneName          null.String       `db:"time_zone_name" json:"time_zone_name"`
	UserAgent             null.String       `db:"user_agent" json:"user_agent"`
	AccessedAt            NullMysqlDateTime `db:"accessed_at" json:"accessed_at"`
	CreatedAt             NullMysqlDateTime `db:"created_at" json:"created_at"`
	ImpersonatorId        null.Int          `db:"impersonator_id" json:"impersonator_id"`
	RevokedAt             NullMysqlDateTime `db:"revoked_at" json:"revoked_at"`
	ExpiresAt             NullMysqlDateTime `db:"expires_at" json:"expires_at"`
	ImpersonatorSessionId null.Int          `db:"impersonator_session_id" json:"impersonator_session_id"`
	SudoEnabledAt         NullMysqlDateTime `db:"sudo_enabled_at" json:"sudo_enabled_at"`
	HashedKey             []byte            `db:"hashed_key" json:"hashed_key"`
	CsrfToken             []byte            `db:"csrf_token" json:"csrf_token"`
	RevokedReason         null.String       `db:"revoked_reason" json:"revoked_reason"`
	Secret                []byte            `db:"secret" json:"secret"`
	HashedPrivateModeKey  []byte            `db:"hashed_private_mode_key" json:"hashed_private_mode_key"`
	HashedGistKey         []byte            `db:"hashed_gist_key" json:"hashed_gist_key"`
}

// user_session expiration is decided by either (whichever comes first):
// - when the session was last accessed + some expiry period (default 2 weeks)
// - the 'expires_at' column
// dotcom implementation: https://github.com/github/github/blob/70d7b0e444369b8d2760846f50bb5d4b518c0664/app/models/user_session.rb#L359
func (u *UserSession) IsExpired(currentTime time.Time) bool {
	if u.ExpiresAt.Valid && !u.ExpiresAt.Time.After(currentTime) {
		return true
	}

	twoWeeksAgo := currentTime.Add(-2 * Week)
	return u.AccessedAt.Time.Before(twoWeeksAgo)
}

// dotcom implementation: https://github.com/github/github/blob/70d7b0e444369b8d2760846f50bb5d4b518c0664/app/models/user_session.rb#L369
func (u *UserSession) IsRevoked() bool {
	return u.RevokedAt.Valid
}

// we don't support impersonated sessions
// dotcom implementation: https://github.com/github/github/blob/70d7b0e444369b8d2760846f50bb5d4b518c0664/app/models/user_session.rb#L475
func (u *UserSession) IsImpersonated() bool {
	return u.ImpersonatorSessionId.Valid
}
