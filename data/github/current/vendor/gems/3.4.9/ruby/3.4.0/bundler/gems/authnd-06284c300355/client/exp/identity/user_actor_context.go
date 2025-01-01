package identity

import "time"

type UserToServerActorContext struct {
	OauthAccess *OauthAccessContext
	// Installation *InstallationContext TODO(zacharysierakowski): Need to add support for installation context for user-to-server token attributes
}

type FineGrainedPersonalAccessTokenActorContext struct {
	ProgrammaticAccessID uint64
	IssuedAt             time.Time
	ExpiresAt            *time.Time
}

type SignedAuthTokenActorContext struct {
	Version   string
	ExpiresAt time.Time
	SessionID *uint64
}
