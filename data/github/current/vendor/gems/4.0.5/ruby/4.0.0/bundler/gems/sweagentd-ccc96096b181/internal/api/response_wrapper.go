package api //nolint:revive // revive doesn't like the package name and I don't care

import (
	"encoding/json"
	"net/http"
)

// ResponseWrapper wraps http.ResponseWriter to capture the status code and error message
type ResponseWrapper struct {
	http.ResponseWriter

	StatusCode  int
	ErrMsg      string
	WroteHeader bool
}

// NewResponseWrapper creates a new ResposneWrapper
func NewResponseWrapper(w http.ResponseWriter) *ResponseWrapper {
	return &ResponseWrapper{
		ResponseWriter: w,
		StatusCode:     http.StatusOK, // default status code
	}
}

// WriteHeader wraps the ResponseWriter WriteHeader method
func (w *ResponseWrapper) WriteHeader(code int) {
	if !w.WroteHeader {
		w.WroteHeader = true
		w.StatusCode = code
		w.ResponseWriter.WriteHeader(code)
	}
}

// Write wraps the ResponseWriter Write method
func (w *ResponseWrapper) Write(b []byte) (int, error) {
	if !w.WroteHeader {
		w.WroteHeader = true
	}
	// Capture error message from response body for non-2xx status codes
	if w.StatusCode >= 400 && w.ErrMsg == "" {
		// Try to parse the error response JSON to extract the message
		var errResp struct {
			Message string `json:"message"`
		}
		if json.Unmarshal(b, &errResp) == nil && errResp.Message != "" {
			w.ErrMsg = errResp.Message
		} else {
			w.ErrMsg = string(b)
		}
	}
	return w.ResponseWriter.Write(b)
}
