package github

import (
	"context"
	"net/http"
	"net/http/httptest"
	"net/http/httputil"
	"net/url"
	"strings"
	"testing"

	"github.com/google/go-github/v65/github"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"golang.org/x/net/html"
)

func Test_extractFormValues(t *testing.T) {
	tests := map[string]struct {
		getsNilNode     bool
		getsHTML        string
		hasActionFilter string
		wantsActionURL  string
		wantsErr        bool
		wantsErrSubstr  string
		wantsFormValues url.Values
	}{
		"should return an error if the provided root is nil": {
			getsNilNode:    true,
			wantsErr:       true,
			wantsErrSubstr: "cannot parse nil HTML node",
		},
		"should return an error if the form action cannot be parsed as a URL": {
			getsHTML:       `<html><body><form action="://"></form></body></html>`,
			wantsErr:       true,
			wantsErrSubstr: "error parsing form action URL",
		},
		"should extract form action and values from the first form when no filter is provided": {
			getsHTML:       `<html><body><form action="/submit"><input name="test1" value="foo" /><input name="test2" value="bar" /></form><form action="/cancel"><input name="test3" value="foo" /><input name="test4" value="bar" /></form></body></html>`,
			wantsActionURL: "/submit",
			wantsFormValues: url.Values{
				"test1": []string{"foo"},
				"test2": []string{"bar"},
			},
		},
		"should extract correct form data when multiple forms are present and an actionFilter is provided": {
			getsHTML:        `<html><body><form action="/submit"><input name="test1" value="foo" /><input name="test2" value="bar" /></form><form action="/cancel"><input name="test3" value="foo" /><input name="test4" value="bar" /></form><form action="/explode"><input name="test5" value="foo" /><input name="test6" value="bar" /></form></body></html>`,
			hasActionFilter: "cancel",
			wantsActionURL:  "/cancel",
			wantsFormValues: url.Values{
				"test3": []string{"foo"},
				"test4": []string{"bar"},
			},
		},
	}

	for name, test := range tests {
		t.Run(name, func(t *testing.T) {
			// I cannot find a way to force `html.Parse` to provide `nil`.
			// Force the behavior for the sake of the test.
			var node *html.Node
			if !test.getsNilNode {
				htmlNode, err := html.Parse(strings.NewReader(test.getsHTML))
				require.NoError(t, err)
				node = htmlNode
			}

			formActionURL, formValues, err := extractFormValues(node, test.hasActionFilter)
			require.Equal(t, test.wantsErr, err != nil)

			if test.wantsErr {
				require.Error(t, err)
				assert.Contains(t, err.Error(), test.wantsErrSubstr)
			} else {
				require.NoError(t, err)
				assert.Equal(t, test.wantsActionURL, formActionURL.String())
				assert.Equal(t, test.wantsFormValues, formValues)
			}
		})
	}
}

func Test_LoginToWebUI(t *testing.T) {
	tests := map[string]struct {
		getsGETBody        string
		getsGETStatusCode  int
		getsPOSTStatusCode int
		wantsErr           bool
		wantsErrSubstr     string
	}{
		"should return an error if the GET to the login page returns a non-200": {
			getsGETStatusCode: http.StatusNotFound,
			wantsErr:          true,
			wantsErrSubstr:    "non-200 returned from login page",
		},
		"should return an invalid credentials message when POSTing to the login returns a 200": {
			getsGETBody:        `<html><body><form action="/session"><input name="test1" value="foo" /><input name="test2" value="bar" /></form></body></html>`,
			getsGETStatusCode:  http.StatusOK,
			getsPOSTStatusCode: http.StatusOK,
			wantsErr:           true,
			wantsErrSubstr:     "invalid login, check credentials and try again",
		},
		"should return a generic error when an unexpected status code is returned after a login attempt": {
			getsGETBody:        `<html><body><form action="/session"><input name="test1" value="foo" /><input name="test2" value="bar" /></form></body></html>`,
			getsGETStatusCode:  http.StatusOK,
			getsPOSTStatusCode: http.StatusInternalServerError,
			wantsErr:           true,
			wantsErrSubstr:     "unexpected status code returned after login attempt",
		},
		"should not return an error on successful login": {
			getsGETBody:        `<html><body><form action="/session"><input name="test1" value="foo" /><input name="test2" value="bar" /></form></body></html>`,
			getsGETStatusCode:  http.StatusOK,
			getsPOSTStatusCode: http.StatusFound,
		},
	}

	for name, test := range tests {
		t.Run(name, func(t *testing.T) {
			// This spins up a HTTP server which the HTTP client in the function will communicate with it.
			// We use it for the following reasons:
			// * Fake HTTP status code
			// * Fake response bodies
			// * Assert that the Client properly sends the form login data
			testServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				if r.Method == http.MethodGet {
					w.WriteHeader(test.getsGETStatusCode)
					w.Write([]byte(test.getsGETBody))
				} else {
					buf, err := httputil.DumpRequest(r, true)
					//nolint:testifylint // HTTP handler is a dummy for test code, using require is fine
					require.NoError(t, err)
					body := string(buf)

					// Maps (url.Values) are unordered
					assert.Contains(t, body, "login=test-username")
					assert.Contains(t, body, "password=test-password")
					assert.Contains(t, body, "test1=foo")
					assert.Contains(t, body, "test2=bar")

					assert.Equal(t, "/session", r.RequestURI)

					w.WriteHeader(test.getsPOSTStatusCode)
				}
			}))
			defer testServer.Close()

			ghClient, err := github.NewClient(testServer.Client()).
				WithEnterpriseURLs(testServer.URL, testServer.URL)
			require.NoError(t, err)
			client := &Client{restClient: ghClient}

			err = client.LoginToWebUI(context.Background(), "test-username", "test-password")

			require.Equal(t, test.wantsErr, err != nil)
			if test.wantsErr {
				require.Error(t, err)
				assert.Contains(t, err.Error(), test.wantsErrSubstr)
			} else {
				require.NoError(t, err)
			}
		})
	}
}
