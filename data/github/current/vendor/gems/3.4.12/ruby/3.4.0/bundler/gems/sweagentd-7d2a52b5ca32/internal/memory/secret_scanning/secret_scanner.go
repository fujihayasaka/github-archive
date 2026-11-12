// Package secretscanning provides functionality to scan memory for secrets using an external scanning service.
package secretscanning

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"mime/multipart"
	"net/http"
	"strconv"

	"github.com/github/go-auth/hmac"
	"github.com/github/sweagentd/internal/memory/core"
	"github.com/github/sweagentd/internal/requestctx"
)

type SecretScanner struct {
	client     HTTPClient
	url        string
	hmacSecret string
}

// HTTPClient interface for mocking HTTP requests
type HTTPClient interface {
	Do(req *http.Request) (*http.Response, error)
}

var _ core.SecretScanner = (*SecretScanner)(nil)

// NewSecretScanner creates a new SecretScanner instance with the provided URL.
func NewSecretScanner(url string, hmacSecret string) *SecretScanner {
	client := &http.Client{}
	return &SecretScanner{
		client:     client,
		url:        url,
		hmacSecret: hmacSecret,
	}
}

// NewSecretScannerWithClient creates a new SecretScanner instance with a custom HTTP client.
func NewSecretScannerWithClient(url string, client HTTPClient, hmacSecret string) *SecretScanner {
	return &SecretScanner{
		client:     client,
		url:        url,
		hmacSecret: hmacSecret,
	}
}

// Scan implements core.SecretScanner.
func (s *SecretScanner) Scan(ctx context.Context, repoNWO core.RepoNWO, memory core.Memory) ([]core.MemorySecret, error) {
	user, ok := requestctx.User(ctx)
	if !ok {
		return nil, fmt.Errorf("user not found in context: %w", core.ErrUnauthorized)
	}
	endpoint := fmt.Sprintf("%s/internal/api/v1/scan/multipart", s.url)
	buffer := &bytes.Buffer{}
	writer := multipart.NewWriter(buffer)

	// Write the fact field
	if err := writer.WriteField("fact", memory.Fact); err != nil {
		return nil, fmt.Errorf("failed to write fact field: %w", err)
	}
	// Write the subject field
	if err := writer.WriteField("subject", memory.Subject); err != nil {
		return nil, fmt.Errorf("failed to write subject field: %w", err)
	}
	// Write the reason field
	if err := writer.WriteField("reason", memory.Reason); err != nil {
		return nil, fmt.Errorf("failed to write reason field: %w", err)
	}

	// Get the content type with boundary before closing
	contentType := writer.FormDataContentType()

	// Close the writer to finalize the multipart data
	if err := writer.Close(); err != nil {
		return nil, fmt.Errorf("failed to close multipart writer: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, buffer)
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}
	req.Header.Set(hmac.RequestHeader, hmac.NewRequestHMAC(s.hmacSecret).String())
	req.Header.Set("X-GitHub-User-Id", strconv.FormatUint(memory.Source.User.ID, 10))
	req.Header.Set("Content-Type", contentType)
	req.Header.Set("X-GITHUB-REPO-NWO", repoNWO.String())
	// For right now, they require a token to just be present, but they use the request HMAC for authentication.
	// We will remove it once we get moved to our own endpoint
	req.Header.Set("Authorization", fmt.Sprintf("Bearer %s", user.TokenInfo.Token))

	resp, err := s.client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("failed to send request: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		bodyString, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("unexpected status code: %d, body: %s", resp.StatusCode, bodyString)
	}

	var response *ScanResponse
	if err := json.NewDecoder(resp.Body).Decode(&response); err != nil {
		return nil, fmt.Errorf("failed to decode response: %w", err)
	}
	return response.ToDomain(repoNWO), nil
}
