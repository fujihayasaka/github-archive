package devicetokens

import (
	"database/sql"

	"github.com/github/notifyd/internal/pkg/mysql"
)

// Tokens represents a list of device tokens.
type Tokens []Token

// Token represents a device token.
type Token struct {
	ID            int64
	UserID        int64
	DeviceToken   string
	OauthAccessID int64
}

type sqlToken struct {
	ID            int32          `db:"id"`
	UserID        int32          `db:"user_id"`
	Service       int32          `db:"service"`
	DeviceToken   string         `db:"device_token"`
	DeviceName    sql.NullString `db:"device_name"`
	OauthAccessID sql.NullInt64  `db:"oauth_access_id"`
	mysql.Timestamps
}

func (s sqlToken) ToToken() Token {
	return Token{
		ID:            int64(s.ID),
		UserID:        int64(s.UserID),
		DeviceToken:   s.DeviceToken,
		OauthAccessID: s.OauthAccessID.Int64,
	}
}
