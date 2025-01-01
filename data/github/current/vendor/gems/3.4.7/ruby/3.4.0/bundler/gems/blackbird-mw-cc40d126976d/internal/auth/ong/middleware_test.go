package ong

import (
	"net/http"
	"net/http/httptest"
	"net/url"
	"testing"

	"github.com/stretchr/testify/require"
)

func Test_AuthWithInvalidSignature(t *testing.T) {
	authedHandlerFunc := Auth("octocat")
	handler := authedHandlerFunc(
		http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			w.WriteHeader(http.StatusOK)
			_, err := w.Write([]byte("hello world"))
			require.NoError(t, err)
		}),
	)

	req, err := http.NewRequest("GET", "/", nil)
	require.NoError(t, err)

	rr := httptest.NewRecorder()
	handler.ServeHTTP(rr, req)

	require.Equal(t, http.StatusUnauthorized, rr.Code)
	require.Empty(t, rr.Body.String())
}

func Test_PathEscape(t *testing.T) {
	u, err := url.Parse("https://blackbird.githubapp.com/users/opslevel%5Bbot%5D")
	require.NoError(t, err)
	require.Equal(t, "/users/opslevel[bot]", u.Path)
	require.Equal(t, "/users/opslevel%5Bbot%5D", u.EscapedPath())
}
