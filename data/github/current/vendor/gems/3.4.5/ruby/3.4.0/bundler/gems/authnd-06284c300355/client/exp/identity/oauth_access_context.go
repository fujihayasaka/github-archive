package identity

import "time"

type OauthAccessContext struct {
	Application *ApplicationContext

	OauthAccessID uint64
	Scopes        []string

	CreatedAt time.Time
	IssuedAt  *time.Time
	ExpiresAt *time.Time
}

func (o *OauthAccessContext) IsPersonalAccessToken() bool {
	return o.Application == nil || o.Application.ID == PersonalAccessTokenApplicationID
}
