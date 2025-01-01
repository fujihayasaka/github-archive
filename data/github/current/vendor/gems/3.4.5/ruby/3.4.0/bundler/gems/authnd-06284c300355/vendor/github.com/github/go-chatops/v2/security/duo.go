package security

import (
	"errors"
	"fmt"
	"time"

	duoapi "github.com/duosecurity/duo_api_golang"
	"github.com/duosecurity/duo_api_golang/authapi"
)

const (
	// DefaultDuoAuthTimeout FIXME: allowing users to set this will break current interface.
	DefaultDuoAuthTimeout = 15 // seconds
)

// DuoTwoFactor implements the two factor calls for Duo.
type DuoTwoFactor struct {
	Duo *duoapi.DuoApi
}

// SendAuthRequest implements security.TwoFactorAuthorizer and calls the DuoAPI to send push.
func (d *DuoTwoFactor) SendAuthRequest(username, command string) (*AuthResponse, error) {
	api := authapi.NewAuthApi(*d.Duo)
	resp, err := api.Auth(
		"push",
		authapi.AuthUsername(fmt.Sprintf("%s@github.com", username)),
		authapi.AuthDevice("auto"),
		authapi.AuthType(command),
		authapi.AuthAsync(),
	)
	if err != nil {
		return nil, err
	}

	msg := fmt.Sprintf("@%s: Duo two-factor auth required.  Please check your mobile device.", username)
	return &AuthResponse{resp.Response.Txid, msg}, nil
}

// CheckStatus implements security.TwoFactorAuthorizer and calls the DuoAPI to check status.
func (d *DuoTwoFactor) CheckStatus(token string) (bool, error) {
	api := authapi.NewAuthApi(*d.Duo)
	for i := 0; i < DefaultDuoAuthTimeout; i++ {
		resp, err := api.AuthStatus(token)
		if err != nil {
			return false, err
		}

		switch resp.Response.Result {
		case "allow":
			return true, nil
		case "deny":
			//nolint:stylecheck // not changing the error message to avoid breaking changes
			return false, errors.New("The user denied the Duo push")
		}

		time.Sleep(1 * time.Second)
	}

	//nolint:stylecheck // not changing the error message to avoid breaking changes
	return false, errors.New("Failed duo auth request for unknown reasons")
}
