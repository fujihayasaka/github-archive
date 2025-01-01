package errors

// ErrorResponse is an error message that is returned from the GitHub API
type ErrorResponse struct {
	Message string `json:"message"`
}
