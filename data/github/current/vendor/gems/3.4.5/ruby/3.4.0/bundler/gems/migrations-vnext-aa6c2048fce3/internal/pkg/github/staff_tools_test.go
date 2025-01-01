package github

import (
	"context"
	"net/http"
	"net/http/httptest"
	"net/http/httputil"
	"testing"

	"github.com/google/go-github/v65/github"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestStaffToolsServiceImpl_UnlockRepository(t *testing.T) {
	tests := map[string]struct {
		getsGETBody        string
		getsGETStatusCode  int
		getsPOSTStatusCode int
		wantsErr           bool
		wantsErrSubstr     string
		wantsPOST          bool
	}{
		"should return an error that the client is not logged in when a 302 is returned from the security page": {
			getsGETStatusCode: http.StatusFound,
			wantsErr:          true,
			wantsErrSubstr:    "client not logged in",
		},
		"should return an error when a non-200 is returned from the security page": {
			getsGETStatusCode: http.StatusInternalServerError,
			wantsErr:          true,
			wantsErrSubstr:    "unexpected status code from security page",
		},
		"should return nil and early when the repository is already unlocked": {
			getsGETBody:       `<html><body><form action="/cancel_unlock"></form></body></html>`,
			getsGETStatusCode: http.StatusOK,
			wantsPOST:         false,
		},
		"should return an error when the unlock form cannot be found": {
			getsGETBody:       `<html><body><form action="/submit"></form></body></html>`,
			getsGETStatusCode: http.StatusOK,
			wantsErr:          true,
			wantsErrSubstr:    "unable to find unlock form on security page",
			wantsPOST:         false,
		},
		"should return an error when POSTing the unlock form returns a non-200": {
			getsGETBody:        `<html><body><form action="/stafftools/repositories/test-owner/test-repo/staff_unlock"><input type="hidden" name="authenticity_token" value="foo" /></form></body></html>`,
			getsGETStatusCode:  http.StatusOK,
			getsPOSTStatusCode: http.StatusBadRequest,
			wantsErr:           true,
			wantsErrSubstr:     "non-200 status code returned from unlock attempt",
			wantsPOST:          true,
		},
		"should return nil when the unlock request returns 200": {
			getsGETBody:        `<html><body><form action="/stafftools/repositories/test-owner/test-repo/staff_unlock"><input type="hidden" name="authenticity_token" value="foo" /></form></body></html>`,
			getsGETStatusCode:  http.StatusOK,
			getsPOSTStatusCode: http.StatusOK,
			wantsPOST:          true,
		},
	}

	for name, test := range tests {
		t.Run(name, func(t *testing.T) {
			// This spins up an HTTP server which the HTTP client in the function will communicate with it.
			// We use it for the following reasons:
			// * Fake HTTP status code
			// * Fake response bodies
			// * Assert that the Client properly sends the form login data
			var didPOST bool
			testServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				if r.Method == http.MethodGet {
					w.WriteHeader(test.getsGETStatusCode)
					w.Write([]byte(test.getsGETBody))
				} else {
					didPOST = true

					buf, err := httputil.DumpRequest(r, true)
					//nolint:testifylint // HTTP handler is a dummy for test code, using require is fine
					require.NoError(t, err)
					body := string(buf)

					// Maps (url.Values) are unordered
					assert.Contains(t, body, "authenticity_token=foo")
					assert.Contains(t, body, "reason=test")

					assert.Equal(t, "/stafftools/repositories/test-owner/test-repo/staff_unlock", r.RequestURI)

					w.WriteHeader(test.getsPOSTStatusCode)
				}
			}))
			defer testServer.Close()

			ghClient, err := github.NewClient(testServer.Client()).
				WithEnterpriseURLs(testServer.URL, testServer.URL)
			require.NoError(t, err)
			client := &Client{StaffTools: &staffToolsServiceImpl{ghClient}}

			err = client.StaffTools.UnlockRepository(context.Background(), "test-owner", "test-repository", "test")

			require.Equal(t, test.wantsErr, err != nil)
			if test.wantsErr {
				require.Error(t, err)
				assert.Contains(t, err.Error(), test.wantsErrSubstr)
			} else {
				assert.Equal(t, test.wantsPOST, didPOST)
				require.NoError(t, err)
			}
		})
	}
}
