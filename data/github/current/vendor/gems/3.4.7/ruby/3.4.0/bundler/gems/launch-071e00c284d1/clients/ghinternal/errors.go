package ghinternal

import "github.com/github/launch/types/errors"

var _ errors.HTTPError = (*APIError)(nil)

// APIError wraps an error from the GitHub API.
type APIError struct {
	StatusCode   int
	ErrorMessage string
}

// MatchStatusCodes sees if the APIError matches the given status code.
func (e *APIError) MatchStatusCodes(codes ...int) bool {
	for _, code := range codes {
		if code == e.StatusCode {
			return true
		}
	}
	return false
}

// Error returns the underlying error message from the API.
func (e *APIError) Error() string {
	return e.ErrorMessage
}

func NewAPIError(statusCode int, message string) error {
	return &APIError{
		StatusCode:   statusCode,
		ErrorMessage: message,
	}
}
