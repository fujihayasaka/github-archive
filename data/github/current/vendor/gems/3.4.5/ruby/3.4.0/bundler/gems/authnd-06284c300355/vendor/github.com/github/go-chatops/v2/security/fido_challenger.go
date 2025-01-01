package security

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/url"
	"strings"
	"time"
)

var (
	// FidoErrEmptyUid is an error for empty UID string.
	//nolint:errname,revive,stylecheck // not renaming an exported error to avoid breaking changes
	FidoErrEmptyUid = errors.New("UID cannot be empty")
	// FidoErrEmptyResource is an error used when the resource string is empty.
	//nolint:errname,stylecheck // not renaming an exported error to avoid breaking changes
	FidoErrEmptyResource = errors.New("Resource cannot be empty")
	// FidoErrTokenNotFound is used when the token is not found.
	//nolint:errname,stylecheck // not renaming an exported error to avoid breaking changes
	FidoErrTokenNotFound = errors.New("Token not found")
	// FidoErrCommunicationError is used when there is an error contacting the FIDO challenger service.
	//nolint:errname,stylecheck // not renaming an exported error to avoid breaking changes
	FidoErrCommunicationError = errors.New("Error contacting FIDO challenger service")

	// FidoStatusSuccess indicates that the Fido challenge was a success.
	FidoStatusSuccess = "success"
)

const (
	// FidoChallengeSuccess indicates the status of the FIDO challenge.
	FidoChallengeSuccess = iota
	// FidoChallengePending indicates the FIDO challenge is pending.
	FidoChallengePending
	// FidoChallengeNotFound indicates the FIDO challenge was not found.
	FidoChallengeNotFound

	// DefaultFidoChallengeTimeout is the default amount of time (in seconds)
	// that the client will poll to determine if a challenge was successful.
	DefaultFidoChallengeTimeout = 30
)

// FidoAuthChallengerClient is a wrapper to help make FIDO Auth
// challenger calls so you don't have to.
type FidoAuthChallengerClient struct {
	httpClient *http.Client
	ServiceURL string
	timeout    int // seconds
}

// FidoAuthChallengerClientOption is a function that can be used to set options on the FidoAuthChallengerClient.
type FidoAuthChallengerClientOption func(*FidoAuthChallengerClient)

// WithTimeout sets the timeout for the FidoAuthChallengerClient.
func WithTimeout(timeout int) FidoAuthChallengerClientOption {
	return func(c *FidoAuthChallengerClient) {
		c.timeout = timeout
	}
}

// FidoChallengerError provides additional context around errors for
// FIDO Auth Challenger.
type FidoChallengerError struct {
	Err     error
	Message string
}

func (e FidoChallengerError) Error() string {
	return e.Message
}

func (e FidoChallengerError) Unwrap() error {
	return e.Err
}

// FidoChallengeResponse is a struct to parse JSON responses from
// the FIDO Auth Challenger /challenge call.
type FidoChallengeResponse struct {
	Token string `json:"token"`
	//nolint:revive,stylecheck // not renaming to avoid breaking changes
	Url string `json:"url"`
}

// FidoChallengeStatusResponse is a struct to parse JSON responses
// from the FIDO Auth Challenger /status call.
type FidoChallengeStatusResponse struct {
	Status string `json:"status"`
}

// NewFidoAuthChallengerClient creates a new FidoAuthChallengerClient with configurable options.
func NewFidoAuthChallengerClient(httpClient *http.Client, serviceURL string, opts ...FidoAuthChallengerClientOption) *FidoAuthChallengerClient {
	client := &FidoAuthChallengerClient{httpClient, serviceURL, DefaultFidoChallengeTimeout}

	for _, opt := range opts {
		opt(client)
	}

	return client
}

// Challenge creates a challenge to authenticate a user with FIDO Challenge Response.
func (c *FidoAuthChallengerClient) Challenge(uid, resource string) (*FidoChallengeResponse, *FidoChallengerError) {
	if len(uid) < 1 {
		// error for empty user string
		return nil, &FidoChallengerError{FidoErrEmptyUid, "Unable to call FIDO Challenger without a username."}
	}
	if len(resource) < 1 {
		// error for empty resource string
		return nil, &FidoChallengerError{FidoErrEmptyResource, "Unable to call FIDO Challenger without a resource."}
	}

	uri := fmt.Sprintf("%s/challenges", c.ServiceURL)
	params := url.Values{"uid": {uid}, "resource": {resource}}
	req, err := http.NewRequestWithContext(context.Background(), http.MethodPost, uri, strings.NewReader(params.Encode()))
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	if err != nil {
		return nil, &FidoChallengerError{err, "Could not create HTTP request to FIDO Challenger."}
	}
	resp, err := c.httpClient.Do(req)
	if err != nil {
		// error handling on http request
		return nil, &FidoChallengerError{err, "HTTP request to FIDO Challenger failed."}
	}

	defer resp.Body.Close()

	var parsedResponse FidoChallengeResponse
	if resp.StatusCode != http.StatusCreated {
		return nil, &FidoChallengerError{FidoErrCommunicationError, "Server returned unexpected response"}
	}
	if err := json.NewDecoder(resp.Body).Decode(&parsedResponse); err != nil {
		// error handling on json parsing
		return nil, &FidoChallengerError{err, "Failed to parse FIDO Challenger Response"}
	}

	return &parsedResponse, nil
}

// parseFidoChallengeStatus is a helper function to split out the parsing
// logic from TokenStatus.
func parseFidoChallengeStatus(resp *http.Response) (int, *FidoChallengerError) {
	defer resp.Body.Close()

	var parsedResponse FidoChallengeStatusResponse
	err := json.NewDecoder(resp.Body).Decode(&parsedResponse)
	if err != nil {
		// error handling on json parsing
		return FidoChallengePending, &FidoChallengerError{err, "Failed to parse FIDO Challenger Status Response"}
	}
	if parsedResponse.Status == FidoStatusSuccess {
		return FidoChallengeSuccess, nil
	}

	return FidoChallengePending, nil
}

// TokenStatus retrieves the status of a pending Challenge.
func (c *FidoAuthChallengerClient) TokenStatus(token string) (int, *FidoChallengerError) {
	uri := fmt.Sprintf("%s/challenges/%s/status", c.ServiceURL, token)
	req, err := http.NewRequestWithContext(context.Background(), http.MethodGet, uri, http.NoBody)
	if err != nil {
		return FidoChallengePending, &FidoChallengerError{err, "Could not create HTTP request to FIDO Challenger."}
	}
	resp, err := c.httpClient.Do(req)
	if err != nil {
		return FidoChallengePending, &FidoChallengerError{err, "Error performing status request"}
	}

	switch status := resp.StatusCode; status {
	case http.StatusOK:
		return parseFidoChallengeStatus(resp)
	case http.StatusNotFound:
		return FidoChallengeNotFound, &FidoChallengerError{FidoErrTokenNotFound, "Was a challenge request created?"}
	default:
		return FidoChallengePending, &FidoChallengerError{FidoErrCommunicationError, "FIDO Challenger returned an unexpected response"}
	}
}

// PollStatus will poll a particular token waiting for the status to change.
func (c *FidoAuthChallengerClient) PollStatus(token string) (int, *FidoChallengerError) {
	status := FidoChallengePending
	for i := 0; i < c.timeout && status == FidoChallengePending; i++ {
		status, err := c.TokenStatus(token)
		if err != nil {
			if status == FidoChallengeNotFound {
				return FidoChallengeNotFound, err
			}
		}

		if status == FidoChallengeSuccess {
			return FidoChallengeSuccess, nil
		}

		time.Sleep(1 * time.Second)
	}

	return FidoChallengePending, nil
}

// SendAuthRequest implements the required call to be compatible with the
// TwoFactorAuthorizer interface.
func (c *FidoAuthChallengerClient) SendAuthRequest(username, command string) (*AuthResponse, error) {
	resp, err := c.Challenge(fmt.Sprintf("%s@github.com", username), command)
	if err != nil {
		return nil, err
	}

	msg := fmt.Sprintf("@%s: FIDO auth required. Please authorize via: %s", username, resp.Url)
	return &AuthResponse{resp.Token, msg}, nil
}

// CheckStatus implements the required call to be compatible with the
// TwoFactorAuthorizer interface.
func (c *FidoAuthChallengerClient) CheckStatus(token string) (bool, error) {
	code, err := c.PollStatus(token)
	if err != nil {
		return false, err
	}

	if code == FidoChallengeSuccess {
		return true, nil
	}

	return false, errors.New("Challenge authentication not successful")
}
