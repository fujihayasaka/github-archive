package security

// AuthResponse represents the response from a generic authentication provider.
type AuthResponse struct {
	Token   string
	Message string
}

// TwoFactorAuthorizer is an interface to an object that can make a two factor auth request
// this lets us inject the implementation details later without having to add a bunch
// of dependencies to this library.
type TwoFactorAuthorizer interface {
	SendAuthRequest(username string, request string) (*AuthResponse, error)
	CheckStatus(token string) (bool, error)
}
