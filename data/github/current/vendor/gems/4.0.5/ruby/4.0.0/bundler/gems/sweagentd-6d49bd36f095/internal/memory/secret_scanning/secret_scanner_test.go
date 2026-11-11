package secretscanning

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"mime"
	"mime/multipart"
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

	secrets, err := ts.scanner.Scan(ts.ctx, ts.repoNWO, &ts.memory)
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

	secrets, err := ts.scanner.Scan(ts.ctx, ts.repoNWO, &ts.memory)
	require.NoError(t, err)

	assert.NotEmpty(t, secrets, "Expected secrets to be found in the scan")
	assert.Len(t, secrets, 1, "Expected exactly one secret to be found")
	assert.Equal(t, secretText, secrets[0].Secret, "Expected the secret to match the one in the fact")
	ts.mockClient.AssertExpectations(t)
}

func TestSecretScanner_ServiceUnavailable(t *testing.T) {
	ts := setupTest()

	// Mock 500 response with a large HTML error page (like GitHub's Unicorn page)
	mockResponse := &http.Response{
		StatusCode: http.StatusInternalServerError,
		Body:       io.NopCloser(bytes.NewReader([]byte("<html><body>Unicorn! We had issues producing the response.</body></html>"))),
	}
	ts.expectScanRequest(mockResponse, nil)

	secrets, err := ts.scanner.Scan(ts.ctx, ts.repoNWO, &ts.memory)
	require.Error(t, err)
	require.ErrorIs(t, err, core.ErrSecretScanningServiceUnavailable)
	assert.Contains(t, err.Error(), "secret scanning service returned 500")
	assert.NotContains(t, err.Error(), "Unicorn")
	assert.Nil(t, secrets)
	ts.mockClient.AssertExpectations(t)
}

func TestSecretScanner_ServiceUnavailable502(t *testing.T) {
	ts := setupTest()

	// Mock 502 Bad Gateway response
	mockResponse := &http.Response{
		StatusCode: http.StatusBadGateway,
		Body:       io.NopCloser(bytes.NewReader([]byte("Bad Gateway"))),
	}
	ts.expectScanRequest(mockResponse, nil)

	secrets, err := ts.scanner.Scan(ts.ctx, ts.repoNWO, &ts.memory)
	require.Error(t, err)
	require.ErrorIs(t, err, core.ErrSecretScanningServiceUnavailable)
	assert.Contains(t, err.Error(), "secret scanning service returned 502")
	assert.Nil(t, secrets)
	ts.mockClient.AssertExpectations(t)
}

func TestSecretScanner_UnexpectedStatusBodyTruncation(t *testing.T) {
	ts := setupTest()

	// Create a body longer than maxBodyLogSize (1024 bytes)
	longBody := strings.Repeat("a", 2000)
	mockResponse := &http.Response{
		StatusCode: http.StatusForbidden,
		Body:       io.NopCloser(bytes.NewReader([]byte(longBody))),
	}
	ts.expectScanRequest(mockResponse, nil)

	secrets, err := ts.scanner.Scan(ts.ctx, ts.repoNWO, &ts.memory)
	require.Error(t, err)
	assert.Contains(t, err.Error(), "unexpected status code: 403")
	assert.Contains(t, err.Error(), "... (truncated)")
	// The error should not contain the full 2000-char body
	assert.Less(t, len(err.Error()), 1200)
	assert.Nil(t, secrets)
	ts.mockClient.AssertExpectations(t)
}

func TestSecretScanner_RepositoryNotFound(t *testing.T) {
	ts := setupTest()

	// Mock 400 response with "repository not found" message
	mockResponse := &http.Response{
		StatusCode: http.StatusBadRequest,
		Body:       io.NopCloser(bytes.NewReader([]byte(`{"error": "repository not found"}`))),
	}
	ts.expectScanRequest(mockResponse, nil)

	secrets, err := ts.scanner.Scan(ts.ctx, ts.repoNWO, &ts.memory)
	require.Error(t, err)
	require.ErrorIs(t, err, core.ErrSecretScanningRepositoryNotFound)
	assert.Nil(t, secrets)
	ts.mockClient.AssertExpectations(t)
}

func TestSecretScanner_OtherBadRequestError(t *testing.T) {
	ts := setupTest()

	// Mock 400 response with a different error message (not repository not found)
	mockResponse := &http.Response{
		StatusCode: http.StatusBadRequest,
		Body:       io.NopCloser(bytes.NewReader([]byte(`{"error": "invalid request format"}`))),
	}
	ts.expectScanRequest(mockResponse, nil)

	secrets, err := ts.scanner.Scan(ts.ctx, ts.repoNWO, &ts.memory)
	require.Error(t, err)
	require.NotErrorIs(t, err, core.ErrSecretScanningRepositoryNotFound)
	assert.Contains(t, err.Error(), "unexpected status code: 400")
	assert.Contains(t, err.Error(), "invalid request format")
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

	secrets, err := ts.scanner.Scan(ts.ctx, ts.repoNWO, &ts.memory)
	require.NoError(t, err)
	assert.Empty(t, secrets)
	ts.mockClient.AssertExpectations(t)
}

func TestSecretScanner_EmptyRepoNWO_OmitsHeader(t *testing.T) {
	ts := setupTest()
	ts.repoNWO = core.RepoNWO{} // empty NWO for user-scoped memories
	ts.memory.Source.NWO = core.RepoNWO{}

	responseData := ScanResponse{
		NumBytesScanned: 100,
		BlobsScanned:    1,
		Secrets:         []Secret{},
	}
	mockResponse := createMockResponse(http.StatusOK, responseData)

	ts.mockClient.On("Do", mock.MatchedBy(func(req *http.Request) bool {
		return req.URL.String() == "https://test-scanning-api.github.com/internal/api/v1/scan/multipart" &&
			req.Header.Get("X-GITHUB-REPO-NWO") == "" &&
			req.Header.Get(hmac.RequestHeader) != "" &&
			strings.Contains(req.Header.Get("Content-Type"), "multipart/form-data")
	})).Return(mockResponse, nil)

	secrets, err := ts.scanner.Scan(ts.ctx, ts.repoNWO, &ts.memory)
	require.NoError(t, err)
	assert.Empty(t, secrets)
	ts.mockClient.AssertExpectations(t)
}

func TestSecretScanner_EmptyRepoNWO_DetectsSecrets(t *testing.T) {
	ts := setupTest()
	ts.repoNWO = core.RepoNWO{} // empty NWO for user-scoped memories
	ts.memory.Source.NWO = core.RepoNWO{}

	secretText := "ghp_abc123secret"
	ts.memory.Fact = fmt.Sprintf("use this token: %s", secretText)

	responseData := ScanResponse{
		NumBytesScanned: 100,
		BlobsScanned:    1,
		Secrets: []Secret{
			{
				Type:  TokenType{Type: "github_personal_access_token", Label: "GitHub PAT"},
				Token: secretText,
			},
		},
	}
	mockResponse := createMockResponse(http.StatusOK, responseData)

	ts.mockClient.On("Do", mock.MatchedBy(func(req *http.Request) bool {
		return req.URL.String() == "https://test-scanning-api.github.com/internal/api/v1/scan/multipart" &&
			req.Header.Get("X-GITHUB-REPO-NWO") == "" &&
			req.Header.Get("Authorization") != "" &&
			strings.HasPrefix(req.Header.Get("Content-Type"), "multipart/")
	})).Return(mockResponse, nil)

	secrets, err := ts.scanner.Scan(ts.ctx, ts.repoNWO, &ts.memory)
	require.NoError(t, err)
	assert.Len(t, secrets, 1)
	assert.Equal(t, secretText, secrets[0].Secret)
	// RepoNWO should be empty on the returned secret
	assert.Equal(t, core.RepoNWO{}, secrets[0].RepoNWO)
	ts.mockClient.AssertExpectations(t)
}

func TestSecretScanner_MultipartPartsIncludeFilename(t *testing.T) {
	ts := setupTest()

	ts.memory.Fact = "my-fact-content"
	ts.memory.Subject = "my-subject-content"
	ts.memory.Reason = "my-reason-content"

	responseData := ScanResponse{
		NumBytesScanned: 100,
		BlobsScanned:    3,
		Secrets:         []Secret{},
	}
	mockResponse := createMockResponse(http.StatusOK, responseData)

	// Capture the request to inspect the multipart body
	var capturedReq *http.Request
	ts.mockClient.On("Do", mock.MatchedBy(func(req *http.Request) bool {
		capturedReq = req
		return true
	})).Return(mockResponse, nil)

	_, err := ts.scanner.Scan(ts.ctx, ts.repoNWO, &ts.memory)
	require.NoError(t, err)
	require.NotNil(t, capturedReq)

	// Parse the multipart body and verify each part has a filename
	contentType := capturedReq.Header.Get("Content-Type")
	_, params, err := mime.ParseMediaType(contentType)
	require.NoError(t, err)
	boundary := params["boundary"]
	require.NotEmpty(t, boundary)

	body, err := io.ReadAll(capturedReq.Body)
	require.NoError(t, err)

	reader := multipart.NewReader(bytes.NewReader(body), boundary)

	expectedParts := []struct {
		name     string
		filename string
		content  string
	}{
		{name: "fact", filename: "fact", content: "my-fact-content"},
		{name: "subject", filename: "subject", content: "my-subject-content"},
		{name: "reason", filename: "reason", content: "my-reason-content"},
	}

	for _, expected := range expectedParts {
		part, err := reader.NextPart()
		require.NoError(t, err, "expected part %q", expected.name)

		assert.Equal(t, expected.name, part.FormName(),
			"part form name should be %q", expected.name)
		assert.Equal(t, expected.filename, part.FileName(),
			"part for %q must include a filename (required by token-scanning-service)", expected.name)

		content, err := io.ReadAll(part)
		require.NoError(t, err)
		assert.Equal(t, expected.content, string(content),
			"part %q content mismatch", expected.name)
	}

	// Ensure no extra parts
	_, err = reader.NextPart()
	require.ErrorIs(t, err, io.EOF, "expected exactly 3 multipart parts")

	ts.mockClient.AssertExpectations(t)
}
