package models

import (
	"time"

	"gopkg.in/guregu/null.v4"
)

type PublicKey struct {
	ID                int64             `db:"id" json:"id"`
	Key               string            `db:"key" json:"key"`
	Title             null.String       `db:"title" json:"title"`
	ReadOnly          null.Int          `db:"read_only" json:"read_only"`
	VerifiedAt        NullMysqlDateTime `db:"verified_at" json:"verified_at"`
	UserID            null.Int          `db:"user_id"`
	RepositoryID      null.Int          `db:"repository_id"`
	FingerprintSHA256 []byte            `db:"fingerprint_sha256"`
}

// IsVerified returns true if the public key was verified and the verification
// time is before the current time.
func (pk *PublicKey) IsVerified() bool {
	return pk.VerifiedAt.Valid && pk.VerifiedAt.Time.Before(time.Now())
}
