// handles shared HTTP client logic for LLM providers.
package provider

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"time"

	"github.com/github/codeml-autofix/go/pkg/autofix"
	"github.com/github/codeml-autofix/go/pkg/autofix/enhancedctx"
	"github.com/github/codeml-autofix/go/pkg/autofix/llm/models"
	"github.com/github/github-telemetry-go/kvp"
)

// LLMClient defines the interface for all LLM clients
type LLMClient interface {
	models.Model
	ValidateRequest(messages []models.ChatMessage) autofix.AutofixError
	BuildEndpointURL(endpoint string) string
	Headers() map[string]string
	Hash() (string, error)
}

// HttpClient defines an interface for HTTP operations
type HttpClient interface {
	Do(req *http.Request) (*http.Response, error)
}

// ModelRegistry defines the interface for model lookup operations
type ModelRegistry interface {
	GetModelByID(id string) (*models.ModelEntry, bool)
	GetModelByFlavor(flavor string) (*models.ModelEntry, bool)
	GetModelIDFromFlavor(flavor string) (string, bool)
}
type BaseClient struct {
	httpClient     HttpClient
	defaultOptions *models.CompletionOptions
}

func (b *BaseClient) Hash() (string, error) {
	return b.defaultOptions.Hash()
}

// BaseClientOption defines a function that configures a BaseClient
type BaseClientOption func(*BaseClient)

// WithHttpClient allows injecting a custom HTTP client
func WithHttpClient(client HttpClient) BaseClientOption {
	return func(b *BaseClient) {
		b.httpClient = client
	}
}

// WithDefaultOptions allows setting default completion options
func WithDefaultOptions(opts *models.CompletionOptions) BaseClientOption {
	return func(b *BaseClient) {
		b.defaultOptions = opts
	}
}

// NewBaseClient creates a new base client with default options
func NewBaseClient(defaultOpts *models.CompletionOptions, options ...BaseClientOption) *BaseClient {
	client := &BaseClient{
		defaultOptions: defaultOpts,
		httpClient:     &http.Client{Timeout: 90 * time.Second}, //nolint:exhaustruct
	}

	for _, option := range options {
		option(client)
	}

	return client
}

// GetDefaultCompletionOptions returns the default completion options
func (b *BaseClient) GetDefaultCompletionOptions() models.CompletionOptions {
	return *b.defaultOptions.Clone()
}

func (b *BaseClient) GetMaxTokens() int {
	return b.GetDefaultCompletionOptions().MaxTokens
}

// Headers provides default implementation of headers method
// Concrete clients should override this
func (b *BaseClient) Headers() map[string]string {
	return map[string]string{
		"Content-Type": "application/json",
	}
}

// doRequest executes an HTTP POST request to the specified endpoint with the given body.
// It returns the response or an error if the request fails.
func (b *BaseClient) doRequest(ctx context.Context, client LLMClient, endpoint string, requestBody interface{}, stream bool) (string, autofix.AutofixError) {
	requestJSON, err := json.Marshal(requestBody)
	if err != nil {
		return "", autofix.NewLogicError(fmt.Sprintf("marshaling request body: %v", err))
	}

	req, err := http.NewRequestWithContext(ctx, "POST", client.BuildEndpointURL(endpoint), bytes.NewReader(requestJSON))
	if err != nil {
		return "", autofix.NewLogicError(fmt.Sprintf("creating request: %v", err))
	}

	for k, v := range client.Headers() {
		req.Header.Set(k, v)
	}

	resp, err := b.httpClient.Do(req)
	if err != nil {
		return "", autofix.NewRetryableError(fmt.Sprintf("executing request: %v", err), time.Second*5)
	}
	defer resp.Body.Close()

	if !isResponseOK(resp) {
		err := handleErrorResponse(ctx, resp, requestJSON)

		enhancedctx.Logger(ctx).WithError(err).Warn(
			"HTTP request failed",
			kvp.Int("http_status_code", resp.StatusCode),
			kvp.String("url", endpoint),
		)

		// Report the error to telemetry
		autofix.ReportErrorToTelemetry(ctx, err)
		return "", err
	}

	if stream {
		return handleStreamResponse(ctx, resp)
	}

	return handleSingleResponse(ctx, resp)
}
