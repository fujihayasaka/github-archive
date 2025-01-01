// Package retriables provides a way to make messages retriable.
package retriables

// MsgType represents the message type
type MsgType string

// Message types
const (
	NotifyType                   MsgType = "hydro-schemas.github.net/hydro.schemas.notifyd.v0.Notify"
	DeliverMobilePushType        MsgType = "hydro-schemas.github.net/hydro.schemas.notifyd.v0.DeliverMobilePush"
	DeliverEmailType             MsgType = "hydro-schemas.github.net/hydro.schemas.notifyd.v0.DeliverEmail"
	DeleteRepositoryType         MsgType = "hydro-schemas.github.net/hydro.schemas.notifyd.v1.DeleteRepository"
	DeleteRepositoryForUsersType MsgType = "hydro-schemas.github.net/hydro.schemas.notifyd.v1.DeleteRepositoryForUsers"
	DeleteUserType               MsgType = "hydro-schemas.github.net/hydro.schemas.notifyd.v1.DeleteUser"
	DeleteUserRepositoriesType   MsgType = "hydro-schemas.github.net/hydro.schemas.notifyd.v1.DeleteUserRepositories"
)
