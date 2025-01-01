package models

import (
	"time"

	"gopkg.in/guregu/null.v4"
)

type MobileAuthRequest struct {
	ID              uint64            `db:"id"`
	UserId          uint64            `db:"user_id"`
	Payload         []byte            `db:"payload"`
	ChallengeNumber null.Int          `db:"challenge_number"`
	CreatedAt       NullMysqlDateTime `db:"created_at_utc"`
	ExpiresAt       NullMysqlDateTime `db:"expires_at_utc"`
	ApprovedAt      NullMysqlDateTime `db:"approved_at_utc"`
	RejectedAt      NullMysqlDateTime `db:"rejected_at_utc"`
	Type            int               `db:"type"`
	FromIpAddress   null.String       `db:"from_ip_address"`
	FromDisplayName null.String       `db:"from_display_name"`
}

// IsExpired returns true if token expiry is set and before or equal current time (UTC)
func (mr *MobileAuthRequest) IsExpired(currentTimeUTC time.Time) bool {
	return mr.ExpiresAt.Valid && !mr.ExpiresAt.Time.After(currentTimeUTC)
}

// IsApproved returns true if mobile auth request is approved
func (mr *MobileAuthRequest) IsApproved(currentTimeUTC time.Time) bool {
	return mr.ApprovedAt.Valid && !mr.ApprovedAt.Time.After(currentTimeUTC)
}

// IsRejected returns true if mobile auth request is rejected
func (mr *MobileAuthRequest) IsRejected(currentTimeUTC time.Time) bool {
	return mr.RejectedAt.Valid && !mr.RejectedAt.Time.After(currentTimeUTC)
}

// IsActive returns true if mobile auth request can still be approved or rejected
func (mr *MobileAuthRequest) IsActive(currentTimeUTC time.Time) bool {
	return !mr.IsExpired(currentTimeUTC) && !mr.IsApproved(currentTimeUTC) && !mr.IsRejected(currentTimeUTC)
}
