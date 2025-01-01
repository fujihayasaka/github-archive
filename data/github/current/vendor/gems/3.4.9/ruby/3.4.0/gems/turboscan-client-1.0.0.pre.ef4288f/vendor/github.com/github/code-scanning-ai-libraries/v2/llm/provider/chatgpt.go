package provider

import (
	"context"
	"fmt"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/github/code-scanning-ai-libraries/v2/enhancedctx"
	"github.com/github/code-scanning-ai-libraries/v2/errors"
	"github.com/github/code-scanning-ai-libraries/v2/llm/config"
	"github.com/github/code-scanning-ai-libraries/v2/llm/models"
	"github.com/github/github-telemetry-go/kvp"
	pkg_errors "github.com/pkg/errors"
)

// AzureHostedAzureGPT is a client for Azure-hosted OpenAI GPT models
type AzureHostedAzureGPT struct {
	modelName   string
	httpClient  HTTPClient // HTTP client for making requests, can be injected for testing
	endpointURL string     // e.g. "https://codeml-openai.openai.azure.com"
	apiKey      string
	defaultOpts *models.CompletionOptions
	retry       bool
}

// NewAIPAzureGPT creates a new Azure OpenAI GPT client with the specified model and options
func NewAIPAzureGPT(modelName string, retry bool, opts *models.CompletionOptions, options ...AzureClientOption) *AzureHostedAzureGPT {
	// Create with defaults
	client := &AzureHostedAzureGPT{ //nolint:exhaustruct // partial initialization by design, fields set via options
		modelName:   modelName,
		defaultOpts: opts,
		httpClient:  &http.Client{Timeout: 10 * time.Minute}, //nolint:exhaustruct // No need for all fields
		retry:       retry,
	}

	// Apply options
	for _, option := range options {
		option(client)
	}

	return client
}

// AzureClientOption defines configuration options for Azure OpenAI clients
type AzureClientOption func(*AzureHostedAzureGPT)

// WithEndpoint allows injecting an endpoint
func WithEndpoint(endpoint string) AzureClientOption {
	return func(c *AzureHostedAzureGPT) {
		c.endpointURL = endpoint
	}
}

// WithAzureAPIKey allows injecting an API key
func WithAzureAPIKey(key string) AzureClientOption {
	return func(c *AzureHostedAzureGPT) {
		c.apiKey = key
	}
}

// Complete performs a chat completion with tools, allowing the model to call tools recursively.
func (a *AzureHostedAzureGPT) Complete(ctx context.Context, messages []models.ChatMessage, tools []models.Tool, options *models.CompletionOptions) (string, []models.ChatMessage, *models.TokenUsage, errors.LLMError) {
	ctx, span := enhancedctx.StartSpan(ctx, "llm.AzureHostedAzureGPT.Complete")
	defer span.End()

	fullEndpoint := fmt.Sprintf("%s/openai/v1/responses?api-version=preview", a.endpointURL)

	client := &ResponsesAPIClient{
		fullEndpoint: fullEndpoint,
		modelName:    a.modelName,
		retry:        a.retry,
		headersFn:    func(c context.Context) map[string]string { return a.headers(c) },
		httpClient:   a.httpClient,
	}
	return client.Complete(ctx, messages, tools, options)
}

// MakeAIPClients creates multiple Azure OpenAI clients from configuration
func MakeAIPClients(ctx context.Context, modelName string, retry bool, defaultCompletionOptions *models.CompletionOptions, cfg *config.ModelConfig) ([]*AzureHostedAzureGPT, error) {
	// key: endpoint base URL (e.g. `https://codeml-openai-sweden-central.openai.azure.com`).
	// value: API key
	endpoints := make(map[string]string)

	// Add default endpoint if key exists
	if cfg.AzureOpenAIKey != "" {
		baseURL := "https://codeml-openai.openai.azure.com"
		endpoints[baseURL] = cfg.AzureOpenAIKey
	}

	// Add additional endpoints from config
	if cfg.AzureModelKeys != "" {
		for _, line := range strings.Split(cfg.AzureModelKeys, "\n") {
			if line = strings.TrimSpace(line); line == "" {
				continue
			}
			parts := strings.Split(line, "=")
			if parts[0] == "" || len(parts) > 3 {
				enhancedctx.Logger(ctx).Debug(fmt.Sprintf("Invalid Azure endpoint config: %s", line))
				continue
			}
			url := parts[0]

			if len(parts) == 1 {
				// Managed identity: only URL, no key
				endpoints[url] = ""
				continue
			}
			key := parts[1]
			// Check if model is supported by this endpoint
			if len(parts) == 2 {
				// no specified models, use this key for all
				endpoints[url] = key
			} else if len(parts) > 2 {
				// a comma-separated list of supported models, we need to check whether modelName is in that list
				supportedModels := strings.Split(parts[2], ",")
				for _, model := range supportedModels {
					if strings.TrimSpace(model) == modelName {
						endpoints[url] = key
						break
					}
				}
			}
		}
	}

	if len(endpoints) == 0 {
		return nil, pkg_errors.Errorf("no API keys for %s provided", modelName)
	}

	clients := make([]*AzureHostedAzureGPT, 0, len(endpoints))
	endpointsString := make([]string, 0, len(endpoints))
	for endpoint, key := range endpoints {
		opts := []AzureClientOption{
			WithEndpoint(endpoint),
		}
		if key != "" {
			opts = append(opts, WithAzureAPIKey(key))
		}
		client := NewAIPAzureGPT(modelName, retry, defaultCompletionOptions, opts...)
		clients = append(clients, client)
		endpointsString = append(endpointsString, endpoint)
	}

	enhancedctx.Logger(ctx).Debug("Created Azure OpenAI clients",
		kvp.Int("count", len(clients)),
		kvp.String("modelName", modelName),
		kvp.String("endpoints", strings.Join(endpointsString, ", ")))

	return clients, nil
}

// headers returns the HTTP headers required for Azure OpenAI requests.
func (a *AzureHostedAzureGPT) headers(ctx context.Context) map[string]string {
	headers := map[string]string{
		"Content-Type": "application/json",
	}
	// Authenticate with API key if present, if not try Azure Managed Identity (MSI) token
	if a.apiKey != "" {
		headers["api-key"] = a.apiKey
	} else if token := os.Getenv("AZURE_MSI_TOKEN"); token != "" {
		headers["Authorization"] = "Bearer " + token
	} else {
		enhancedctx.Logger(ctx).Warn("No suitable authentication method found for AzureGPT client")
	}
	return headers
}

// GetModelName returns the string representation of the Azure GPT model name
func (a *AzureHostedAzureGPT) GetModelName() string {
	return a.modelName
}

// GetProviderName returns the provider name for Azure OpenAI
func (a *AzureHostedAzureGPT) GetProviderName() string {
	return "Azure OpenAI"
}
