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
	"strings"
	"time"

	"github.com/github/go-auth/hmac"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/memory/core"
	"github.com/github/sweagentd/internal/requestctx"
)

// SecretScanner implements the core.SecretScanner interface using an external scanning service.
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

// Default HTTP client settings for the secret scanning service.
// These are tuned to maximise connection reuse (avoiding repeated TLS
// handshakes) and to bound the total time a single scan request can take.
// Dial, keep-alive, and TLS handshake timeouts are inherited from
// http.DefaultTransport (which we clone) and are not overridden here.
const (
	// clientTimeout is the overall request timeout (includes dial, TLS, send, read).
	clientTimeout = 10 * time.Second
	// maxIdleConns is the maximum number of idle connections across all hosts.
	maxIdleConns = 10
	// maxIdleConnsPerHost is the maximum number of idle connections to the
	// scanning service host. Because we only talk to one host this should
	// equal maxIdleConns.
	maxIdleConnsPerHost = 10
	// idleConnTimeout is how long an idle connection is kept before closing.
	idleConnTimeout = 90 * time.Second
)

// newScannerHTTPClient creates an *http.Client that is optimised for
// long-lived, repeated requests to the secret scanning service.
//
// It clones http.DefaultTransport so that proxy support (HTTP_PROXY /
// HTTPS_PROXY / NO_PROXY) and HTTP/2 negotiation are preserved, then
// overrides the pooling and timeout knobs so that TLS handshakes are
// amortised across many requests.
func newScannerHTTPClient() *http.Client {
	// Clone DefaultTransport to preserve its Proxy, DialContext, TLS,
	// and HTTP/2 settings as a baseline.
	baseTransport, ok := http.DefaultTransport.(*http.Transport)
	if !ok {
		// Defensive: if DefaultTransport was replaced with something
		// unexpected, fall back to a plain Transport (still better
		// than no pooling config at all).
		baseTransport = &http.Transport{}
	}
	transport := baseTransport.Clone()

	// Override connection-pool and timeout settings.
	transport.MaxIdleConns = maxIdleConns
	transport.MaxIdleConnsPerHost = maxIdleConnsPerHost
	transport.IdleConnTimeout = idleConnTimeout

	return &http.Client{
		Timeout:   clientTimeout,
		Transport: transport,
	}
}

// NewSecretScanner creates a new SecretScanner instance with the provided URL.
// The returned scanner uses an HTTP client configured for connection reuse so
// that TLS handshake cost is paid only once for the lifetime of the scanner.
func NewSecretScanner(url, hmacSecret string) *SecretScanner {
	return &SecretScanner{
		client:     newScannerHTTPClient(),
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
func (s *SecretScanner) Scan(ctx context.Context, repoNWO core.RepoNWO, memory *core.Memory) ([]core.MemorySecret, error) {
	user, ok := requestctx.User(ctx)
	if !ok {
		return nil, goerrors.Errorf("user not found in context: %w", core.ErrUnauthorized)
	}
	endpoint := fmt.Sprintf("%s/internal/api/v1/scan/multipart", s.url)
	buffer := &bytes.Buffer{}
	writer := multipart.NewWriter(buffer)

	// Write fields as file parts so each has a filename in the Content-Disposition
	// header. The token-scanning-service uses the filename as the BlobOID key and
	// rejects parts without one.
	err := writeFilePart(writer, "fact", memory.Fact)
	if err != nil {
		return nil, goerrors.Errorf("failed to write fact part: %w", err)
	}
	err = writeFilePart(writer, "subject", memory.Subject)
	if err != nil {
		return nil, goerrors.Errorf("failed to write subject part: %w", err)
	}
	err = writeFilePart(writer, "reason", memory.Reason)
	if err != nil {
		return nil, goerrors.Errorf("failed to write reason part: %w", err)
	}

	// Get the content type with boundary before closing
	contentType := writer.FormDataContentType()

	// Close the writer to finalize the multipart data
	err = writer.Close()
	if err != nil {
		return nil, goerrors.Errorf("failed to close multipart writer: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, buffer)
	if err != nil {
		return nil, goerrors.Errorf("failed to create request: %w", err)
	}
	req.Header.Set(hmac.RequestHeader, hmac.NewRequestHMAC(s.hmacSecret).String())
	req.Header.Set("X-GitHub-User-Id", strconv.FormatUint(memory.Source.User.ID, 10))
	req.Header.Set("Content-Type", contentType)
	if repoNWO.Owner != "" && repoNWO.Repo != "" {
		req.Header.Set("X-GITHUB-REPO-NWO", repoNWO.String())
	}
	// For right now, they require a token to just be present, but they use the request HMAC for authentication.
	// We will remove it once we get moved to our own endpoint
	req.Header.Set("Authorization", fmt.Sprintf("Bearer %s", user.TokenInfo.Token))

	resp, err := s.client.Do(req)
	if err != nil {
		return nil, goerrors.Errorf("failed to send request: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		// Treat 5xx responses as service unavailable - these often contain large HTML error pages
		// (e.g. GitHub's Unicorn page) that provide no useful debugging context.
		// Check status code before reading the body to avoid buffering large payloads during outages.
		if resp.StatusCode >= http.StatusInternalServerError {
			// Drain the body without buffering to allow connection reuse.
			_, _ = io.Copy(io.Discard, resp.Body)
			return nil, goerrors.Errorf("secret scanning service returned %d: %w", resp.StatusCode, core.ErrSecretScanningServiceUnavailable)
		}
		bodyString, _ := io.ReadAll(resp.Body)
		// Check for repository not found error from the secret scanning service
		if resp.StatusCode == http.StatusBadRequest && containsRepositoryNotFound(string(bodyString)) {
			return nil, goerrors.Errorf("secret scanning service error: %w", core.ErrSecretScanningRepositoryNotFound)
		}
		return nil, goerrors.Errorf("unexpected status code: %d, body: %s", resp.StatusCode, truncateBody(string(bodyString)))
	}

	var response *ScanResponse
	err = json.NewDecoder(resp.Body).Decode(&response)
	if err != nil {
		return nil, goerrors.Errorf("failed to decode response: %w", err)
	}
	return response.ToDomain(repoNWO), nil
}

// maxBodyLogSize is the maximum number of bytes from a response body to include in error messages.
const maxBodyLogSize = 1024

// containsRepositoryNotFound checks if the response body contains a "repository not found" message.
func containsRepositoryNotFound(body string) bool {
	return strings.Contains(strings.ToLower(body), "repository not found")
}

// truncateBody truncates the response body to a reasonable length for logging.
func truncateBody(body string) string {
	if len(body) > maxBodyLogSize {
		return body[:maxBodyLogSize] + "... (truncated)"
	}
	return body
}

// writeFilePart creates a multipart file part with the given field name used as
// both the form name and filename, then writes content into it. The token-scanning
// service requires a filename in the Content-Disposition header to derive the BlobOID.
func writeFilePart(writer *multipart.Writer, fieldName, content string) error {
	part, err := writer.CreateFormFile(fieldName, fieldName)
	if err != nil {
		return err
	}
	_, err = part.Write([]byte(content))
	return err
}
