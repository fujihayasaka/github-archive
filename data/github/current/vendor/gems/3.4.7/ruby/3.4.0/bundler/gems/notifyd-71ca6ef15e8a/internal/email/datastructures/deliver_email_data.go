package datastructures

const (
	// MuteAuthScope represents the mute_auth scope.
	MuteAuthScope string = "mute_auth"
	// MuteListScope represents the mute_list scope.
	MuteListScope string = "mute_list"
	// EmailReplyScope represents the EmailReply scope.
	EmailReplyScope string = "EmailReply"
)

// DeliverEmailData represents a data structure for handling email auth tokens.
type DeliverEmailData struct {
	IsDeliverable        bool
	NotDeliverableReason string
	Email                string
	Login                string
	AuthTokens           []AuthToken
}

// ReplyToToken is a helper function to return the reply-to token from the list of auth tokens.
func (d DeliverEmailData) ReplyToToken() string {
	for _, token := range d.AuthTokens {
		if token.Scope == EmailReplyScope {
			return token.Token
		}
	}
	return ""
}

// AuthToken represents an authorization token.
type AuthToken struct {
	Scope string
	Token string
}
