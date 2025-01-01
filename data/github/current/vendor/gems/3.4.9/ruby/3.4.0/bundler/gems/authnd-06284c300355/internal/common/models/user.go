package models

import (
	"time"

	"gopkg.in/guregu/null.v4"
)

type User struct {
	ID                      int64             `db:"id" json:"id"`
	Login                   string            `db:"login" json:"login"`
	Type                    string            `db:"type" json:"type"`
	BcryptAuthToken         null.String       `db:"bcrypt_auth_token" json:"bcrypt_auth_token"`
	PasswordHash            []byte            `db:"password_hash" json:"password_hash"`
	WeakPasswordCheckResult []byte            `db:"weak_password_check_result" json:"weak_password_check_result"`
	TokenSecret             null.String       `db:"token_secret" json:"token_secret"`
	CreatedAt               NullMysqlDateTime `db:"created_at" json:"created_at"`
	SuspendedAt             NullMysqlDateTime `db:"suspended_at" json:"suspended_at"`
	Disabled                null.Int          `db:"disabled" json:"disabled"`
	Spammy                  null.Int          `db:"spammy" json:"spammy"`
}

func (u *User) IsSuspended() bool {
	return u.SuspendedAt.Valid && u.SuspendedAt.Time.Before(time.Now())
}
