package secretscanning

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"testing"

	authd "github.com/github/authnd/client"
	"github.com/github/go-auth/hmac"
	"github.com/github/sweagentd/internal/memory/core"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
)

// MockHTTPClient is a mock implementation of HTTPClient
type MockHTTPClient struct {
	mock.Mock
}

func (m *MockHTTPClient) Do(req *http.Request) (*http.Response, error) {
	args := m.Called(req)
	return args.Get(0).(*http.Response), args.Error(1)
}

// testSetup contains common test setup data
type testSetup struct {
	mockClient *MockHTTPClient
	scanner    *SecretScanner
	ctx        context.Context
	repoNWO    core.RepoNWO
	memory     core.Memory
}

func createTestContext() context.Context {
	return requestctx.AddData(context.Background(), &requestctx.CtxData{
		UserInfo: &requestctx.UserInfo{
			ID: 1,
			TokenInfo: &requestctx.TokenInfo{
				Type:          string(authd.CredentialTypeUserToServerToken),
				ApplicationID: 1,
				Token:         "test-token",
			},
			Login:      "testuser",
			TrackingID: "tracking-id",
		},
	})
}

// setupTest creates a common test setup with default values
func setupTest() *testSetup {
	mockClient := new(MockHTTPClient)
	url := "https://test-scanning-api.github.com"
	hmacSecret := "keyboard_cat"
	scanner := NewSecretScannerWithClient(url, mockClient, hmacSecret)

	return &testSetup{
		mockClient: mockClient,
		scanner:    scanner,
		ctx:        createTestContext(),
		repoNWO:    core.RepoNWO{Owner: "github", Repo: "sweagentd"},
		memory: core.Memory{
			Source: core.MemorySource{
				NWO: core.RepoNWO{Owner: "owner", Repo: "repo"},
				User: core.User{
					ID: 1,
				},
			},
			Subject: "test_subject",
			Fact:    "test_fact",
			Reason:  "test_reason",
		},
	}
}

// createMockResponse creates a mock HTTP response with the given data
func createMockResponse(statusCode int, responseData any) *http.Response {
	var body io.ReadCloser
	if responseData != nil {
		responseBody, err := json.Marshal(responseData)
		if err != nil {
			panic(fmt.Sprintf("failed to marshal response data: %v", err))
		}
		body = io.NopCloser(bytes.NewReader(responseBody))
	} else {
		body = io.NopCloser(bytes.NewReader([]byte("Internal Server Error")))
	}

	return &http.Response{
		StatusCode: statusCode,
		Body:       body,
	}
}

// expectScanRequest sets up the mock expectation for a scan request
func (ts *testSetup) expectScanRequest(response *http.Response, err error) {
	ts.mockClient.On("Do", mock.MatchedBy(func(req *http.Request) bool {
		return req.URL.String() == "https://test-scanning-api.github.com/internal/api/v1/scan/multipart" &&
			req.Header.Get(hmac.RequestHeader) != "" &&
			req.Header.Get("X-GitHub-User-Id") == "1" &&
			strings.Contains(req.Header.Get("Content-Type"), "multipart/form-data")
	})).Return(response, err)
}

func TestSecretScanner_NoSecretsFound(t *testing.T) {
	ts := setupTest()

	// Mock response with no secrets
	responseData := ScanResponse{
		NumBytesScanned: 100,
		BlobsScanned:    1,
		Secrets:         []Secret{},
	}
	mockResponse := createMockResponse(http.StatusOK, responseData)
	ts.expectScanRequest(mockResponse, nil)

	secrets, err := ts.scanner.Scan(ts.ctx, ts.repoNWO, ts.memory)
	require.NoError(t, err)

	assert.Empty(t, secrets, "Expected no secrets to be found in the sample scan")
	ts.mockClient.AssertExpectations(t)
}

func TestSecretScanner_WithSecret(t *testing.T) {
	ts := setupTest()

	secretText := "keyboard_cat"
	fact := fmt.Sprintf("hi lorem ipsum %s", secretText)

	// Override the default memory fact with our test data
	ts.memory.Fact = fact

	// Mock response with a secret
	responseData := ScanResponse{
		NumBytesScanned: 100,
		BlobsScanned:    1,
		Secrets: []Secret{
			{
				Type: TokenType{
					Type:         "github_token",
					Label:        "GitHub Token",
					ProviderName: "GitHub",
					Slug:         "github-token",
					Confidence:   "high",
				},
				Token:      secretText,
				TokenBytes: []byte(secretText),
				Location: Location{
					FilePath:    "test.txt",
					StartLine:   1,
					EndLine:     1,
					StartColumn: 15,
					EndColumn:   65,
				},
			},
		},
	}
	mockResponse := createMockResponse(http.StatusOK, responseData)
	ts.expectScanRequest(mockResponse, nil)

	secrets, err := ts.scanner.Scan(ts.ctx, ts.repoNWO, ts.memory)
	require.NoError(t, err)

	assert.NotEmpty(t, secrets, "Expected secrets to be found in the scan")
	assert.Len(t, secrets, 1, "Expected exactly one secret to be found")
	assert.Equal(t, secretText, secrets[0].Secret, "Expected the secret to match the one in the fact")
	ts.mockClient.AssertExpectations(t)
}

func TestSecretScanner_HTTPError(t *testing.T) {
	ts := setupTest()

	// Mock HTTP error response
	mockResponse := createMockResponse(http.StatusInternalServerError, nil)
	ts.mockClient.On("Do", mock.AnythingOfType("*http.Request")).Return(mockResponse, nil)

	secrets, err := ts.scanner.Scan(ts.ctx, ts.repoNWO, ts.memory)
	require.Error(t, err)
	assert.Contains(t, err.Error(), "unexpected status code: 500")
	assert.Nil(t, secrets)
	ts.mockClient.AssertExpectations(t)
}

func TestSecretScanner_InvalidUserID(t *testing.T) {
	ts := setupTest()

	// Override memory to have empty user ID
	ts.memory.Source.User.ID = 0

	// Mock response that shouldn't be called
	responseData := ScanResponse{
		NumBytesScanned: 100,
		BlobsScanned:    1,
		Secrets:         []Secret{},
	}
	mockResponse := createMockResponse(http.StatusOK, responseData)

	// Expect a request with empty user ID header
	ts.mockClient.On("Do", mock.MatchedBy(func(req *http.Request) bool {
		return req.URL.String() == "https://test-scanning-api.github.com/internal/api/v1/scan/multipart" &&
			req.Header.Get(hmac.RequestHeader) != "" &&
			req.Header.Get("X-GitHub-User-Id") == "0" &&
			strings.Contains(req.Header.Get("Content-Type"), "multipart/form-data")
	})).Return(mockResponse, nil)

	secrets, err := ts.scanner.Scan(ts.ctx, ts.repoNWO, ts.memory)
	require.NoError(t, err)
	assert.Empty(t, secrets)
	ts.mockClient.AssertExpectations(t)
}
