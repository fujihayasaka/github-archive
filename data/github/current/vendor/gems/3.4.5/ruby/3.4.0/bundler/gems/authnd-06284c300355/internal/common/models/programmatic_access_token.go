package models

type ProgrammaticAccessToken struct {
	HashedToken []byte            `db:"hashed_token"`
	TokenSuffix []byte            `db:"token_suffix"`
	AccessID    uint64            `db:"access_id"`
	LastEventAt NullMysqlDateTime `db:"last_event_at_utc"`
	*MintTokenCommon
}
