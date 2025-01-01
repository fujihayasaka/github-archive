package auth

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/github/github-telemetry-go/log"
	"github.com/stretchr/testify/assert"
)

func TestNewAuthenticationMiddleware_Success(t *testing.T) {
	cfg := ClientConfig{
		ClientID: "npm/read",
		Domain:   "npm",
		Keys:     []string{"mysecret"},
	}
	mw, err := NewAuthenticationMiddleware(log.NewNullLogger(), []ClientConfig{cfg})
	assert.Nil(t, err)
	assert.NotNil(t, mw)
}

func TestNewAuthenticationMiddleware_EmptyAuthCfg(t *testing.T) {
	mw, err := NewAuthenticationMiddleware(log.NewNullLogger(), []ClientConfig{})
	assert.NotNil(t, err)
	assert.Nil(t, mw)
}

// Test that the middleware adds the client ID and domain to the request
// context as expected
func TestMakeSetClientIDMiddleware(t *testing.T) {
	cfg := []ClientConfig{{
		ClientID: "npm/read",
		Domain:   "npm",
		Keys:     []string{"mysecret"},
	},
		{
			ClientID: "uploading-worker",
			Domain:   "npm",
			Keys:     []string{"myothersecret"},
		},
	}

	// test handler that the middleware passes the request to
	assertHandler := func(_ http.ResponseWriter, r *http.Request) {
		ctx := r.Context()
		currentClient, ok := ctx.Value(ctxCurrentClientKey{}).(ServiceClient)
		assert.True(t, ok)

		assert.Equal(t, "uploading-worker", currentClient.ClientID)
		assert.Equal(t, "npm", currentClient.Domain)
		assert.Equal(t, uint32(1), currentClient.DomainID)
	}

	// create a test request that sets a client header the middleware
	// will parse and then update the request based on its value
	req, err := http.NewRequest("GET", "test", nil)
	if err != nil {
		t.Fatal(err)
	}
	req.Header.Set(HMACClientHeader, "uploading-worker")

	// initialize the middleware and call it on the test request with the
	// test assertions handler
	mw := makeSetClientMiddleware(cfg)
	mw(http.HandlerFunc(assertHandler)).ServeHTTP(httptest.NewRecorder(), req)
}

func TestAuthConfigValid(t *testing.T) {
	type test struct {
		expectTestToPass bool
		cfg              ClientConfig
	}

	testcases := []test{
		// cfg should pass validity test
		{
			expectTestToPass: true,
			cfg: ClientConfig{
				ClientID: "someclient",
				Domain:   "somedomain",
				Keys:     []string{"123abc"},
			},
		},
		// empty keys slice should fail validity test
		{
			expectTestToPass: false,
			cfg: ClientConfig{
				ClientID: "someclient",
				Domain:   "somedomain",
				Keys:     []string{},
			},
		},
		// empty key in key slice should fail validity test
		{
			expectTestToPass: false,
			cfg: ClientConfig{
				ClientID: "someclient",
				Domain:   "somedomain",
				Keys:     []string{""},
			},
		},
		// nil keys slice should fail validity test
		{
			expectTestToPass: false,
			cfg: ClientConfig{
				ClientID: "someclient",
				Domain:   "somedomain",
			},
		},
		// empty ClientID field should fail validity test
		{
			expectTestToPass: false,
			cfg: ClientConfig{
				Domain: "somedomain",
				Keys:   []string{"123abc"},
			},
		},
		// empty Domain field should fail validity test
		{
			expectTestToPass: false,
			cfg: ClientConfig{
				ClientID: "someclient",
				Keys:     []string{"123abc"},
			},
		},
	}

	for _, tc := range testcases {
		err := tc.cfg.Valid()

		if tc.expectTestToPass {
			assert.Nil(t, err)
		} else {
			assert.NotNil(t, err)
		}
	}
}

func TestFromGitHub(t *testing.T) {
	// Create a ServiceClient with a GitHub domain ID
	client := &ServiceClient{DomainID: githubDomainID}

	// Call FromGitHub and assert that it returns true
	if !client.FromGitHub() {
		t.Errorf("Expected FromGitHub to return true")
	}

	// Create a ServiceClient with a different domain ID
	client = &ServiceClient{DomainID: 3}

	// Call FromGitHub and assert that it returns false
	if client.FromGitHub() {
		t.Errorf("Expected FromGitHub to return false")
	}
}

func TestFromNpm(t *testing.T) {
	// Create a ServiceClient with an npm domain ID
	client := &ServiceClient{DomainID: npmDomainID}

	// Call FromNpm and assert that it returns true
	if !client.FromNpm() {
		t.Errorf("Expected FromNpm to return true")
	}

	// Create a ServiceClient with a different domain ID
	client = &ServiceClient{DomainID: 3}

	// Call FromNpm and assert that it returns false
	if client.FromNpm() {
		t.Errorf("Expected FromNpm to return false")
	}
}

func TestGetCurrentClient(t *testing.T) {
	// Create a ServiceClient to use in the test
	client := ServiceClient{DomainID: npmDomainID}

	// Create a context with the ServiceClient
	ctx := context.WithValue(context.Background(), ctxCurrentClientKey{}, client)

	// Call GetCurrentClient and assert that it returns the ServiceClient
	result, err := GetCurrentClient(ctx)
	if err != nil {
		t.Errorf("Unexpected error: %v", err)
	}
	if result != client {
		t.Errorf("Unexpected result: %v", result)
	}

	// Create a context without a ServiceClient
	ctx = context.Background()

	// Call GetCurrentClient and assert that it returns an error
	_, err = GetCurrentClient(ctx)
	if !errors.Is(err, ErrNoServiceClient) {
		t.Errorf("Expected error: %v, but got: %v", ErrNoServiceClient, err)
	}
}

func TestMakeFetchKeys(t *testing.T) {
	cfg := []ClientConfig{
		{
			ClientID: "client1",
			Keys:     []string{"key1", "key2"},
		},
		{
			ClientID: "client2",
			Keys:     []string{"key3", "key4"},
		},
	}

	fetchKeys := makeFetchKeys(cfg)

	// Test with a valid client ID
	req, _ := http.NewRequest("GET", "http://example.com", nil)
	req.Header.Set(HMACClientHeader, "client1")
	keys, err := fetchKeys(req)
	assert.Nil(t, err)
	assert.Equal(t, []string{"key1", "key2"}, keys)

	// Test with an invalid client ID
	req.Header.Set(HMACClientHeader, "invalid")
	_, err = fetchKeys(req)
	assert.NotNil(t, err)

	// Test with an empty client ID
	req.Header.Set(HMACClientHeader, "")
	_, err = fetchKeys(req)
	assert.NotNil(t, err)
}

func TestDomainIDs(t *testing.T) {
	// Test that the domain identifiers are as expected
	assert.Equal(t, 1, npmDomainID, "NPM Domain ID should be 1")
	assert.Equal(t, 2, githubDomainID, "GitHub Domain ID should be 2")
}
