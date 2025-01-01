// client for Azure OpenAI ChatGPT models.
package provider

import (
	"context"
	"fmt"
	"strings"

	"github.com/github/codeml-autofix/go/pkg/autofix"
	"github.com/github/codeml-autofix/go/pkg/autofix/config"
	"github.com/github/codeml-autofix/go/pkg/autofix/enhancedctx"
	"github.com/github/codeml-autofix/go/pkg/autofix/llm/models"
)

// ChatGPTFlavor represents Azure OpenAI model types
type ChatGPTFlavor string

const (
	ChatGPT4      ChatGPTFlavor = "chatgpt-4"
	ChatGPT432k   ChatGPTFlavor = "chatgpt-4-32k"
	ChatGPT4Turbo ChatGPTFlavor = "chatgpt-4-turbo"
)

// Model context windows
var ChatGPTContextWindowSizes = map[ChatGPTFlavor]int{
	ChatGPT4:      8192,
	ChatGPT432k:   32768,
	ChatGPT4Turbo: 128000,
}

var ChatGPTFlavorToGeneration = map[ChatGPTFlavor]string{
	ChatGPT4:      "gpt-4",
	ChatGPT432k:   "gpt-4-32k",
	ChatGPT4Turbo: "gpt-4-turbo",
}

func (a *AzureHostedChatGPT) ValidateRequest(messages []models.ChatMessage) autofix.AutofixError {
	if len(messages) == 0 {
		return autofix.NewInvalidRequestError("no messages provided")
	}
	if messages[len(messages)-1].Role != models.ChatMessageRoleUser {
		return autofix.NewInvalidRequestError("last message must be from user")
	}
	return nil
}

type AzureHostedChatGPT struct {
	*BaseClient
	modelName         ChatGPTFlavor
	contextWindowSize int
	modelGeneration   string
	endpointName      string
	apiKey            string
}

func NewAIPChatGPT(modelName ChatGPTFlavor, options ...AzureClientOption) *AzureHostedChatGPT {
	// Create with defaults
	client := &AzureHostedChatGPT{ //nolint:exhaustruct
		modelName:         modelName,
		contextWindowSize: ChatGPTContextWindowSizes[modelName],
		modelGeneration:   ChatGPTFlavorToGeneration[modelName],
	}

	// Apply options
	for _, option := range options {
		option(client)
	}

	// Initialize baseClient if not provided
	if client.BaseClient == nil {
		client.BaseClient = NewBaseClient(&models.DefaultCompletionOptions)
	}

	return client
}

// Add Azure ClientOption pattern
type AzureClientOption func(*AzureHostedChatGPT)

// WithEndpoint allows injecting an endpoint
func WithEndpoint(endpoint string) AzureClientOption {
	return func(c *AzureHostedChatGPT) {
		c.endpointName = endpoint
	}
}

// WithAzureAPIKey allows injecting an API key
func WithAzureAPIKey(key string) AzureClientOption {
	return func(c *AzureHostedChatGPT) {
		c.apiKey = key
	}
}

// WithAzureBaseClient allows injecting a base client
func WithAzureBaseClient(baseClient *BaseClient) AzureClientOption {
	return func(c *AzureHostedChatGPT) {
		c.BaseClient = baseClient
	}
}

func (a *AzureHostedChatGPT) Complete(ctx context.Context, messages []models.ChatMessage) (string, autofix.AutofixError) {
	ctx, span := enhancedctx.StartSpan(ctx, "llm.AzureHostedChatGPT.Complete")
	defer span.End()

	opts := a.GetDefaultCompletionOptions()
	return a.CompleteWithOptions(ctx, messages, &opts)
}

func (a *AzureHostedChatGPT) CompleteWithOptions(ctx context.Context, messages []models.ChatMessage, options *models.CompletionOptions) (string, autofix.AutofixError) {
	ctx, span := enhancedctx.StartSpan(ctx, "llm.AzureHostedChatGPT.CompleteWithOptions")
	defer span.End()

	if err := a.ValidateRequest(messages); err != nil {
		return "", err
	}

	var actualOpts *models.CompletionOptions
	if options != nil {
		actualOpts = options
	} else {
		defaultOpts := a.GetDefaultCompletionOptions()
		actualOpts = &defaultOpts
	}

	reqBody := map[string]interface{}{
		"messages":    messages,
		"max_tokens":  actualOpts.MaxTokens,
		"temperature": actualOpts.Temperature,
		"stream":      actualOpts.Stream,
	}

	return a.doRequest(ctx, a, a.endpointName, reqBody, actualOpts.Stream)
}

func getEndpointURL(modelName ChatGPTFlavor, baseURL string) string {
	baseURL = strings.TrimSuffix(baseURL, "/")

	switch modelName {
	case ChatGPT4:
		return fmt.Sprintf("%s/openai/deployments/gpt-4/chat/completions?api-version=2024-02-01", baseURL)
	case ChatGPT432k:
		return fmt.Sprintf("%s/openai/deployments/gpt-4-32k/chat/completions?api-version=2024-02-01", baseURL)
	case ChatGPT4Turbo:
		return fmt.Sprintf("%s/openai/deployments/chatgpt-4-turbo/chat/completions?api-version=2024-02-01", baseURL)
	default:
		return ""
	}
}

func MakeAIPClients(ctx context.Context, modelName ChatGPTFlavor, defaultOpts *models.CompletionOptions, cfg *config.Config) ([]*AzureHostedChatGPT, error) {
	endpoints := make(map[string]string)

	// Add default endpoint if key exists
	if cfg.AzureOpenAIKey != "" {
		defaultURL := "https://codeml-openai.openai.azure.com"
		endpoints[getEndpointURL(modelName, defaultURL)] = cfg.AzureOpenAIKey
	}

	// Add additional endpoints from config
	if cfg.AzureModelKeys != "" {
		for _, line := range strings.Split(cfg.AzureModelKeys, "\n") {
			if line = strings.TrimSpace(line); line == "" {
				continue
			}
			parts := strings.Split(line, "=")
			if len(parts) < 2 {
				enhancedctx.Logger(ctx).Debug(fmt.Sprintf("Invalid Azure endpoint config: %s", line))
				continue
			}

			url, key := parts[0], parts[1]
			// Check if model is supported by this endpoint
			if len(parts) == 2 || strings.Contains(parts[2], string(modelName)) {
				endpoints[getEndpointURL(modelName, url)] = key
			}
		}
	}

	if len(endpoints) == 0 {
		return nil, fmt.Errorf("no API keys for %s provided", modelName)
	}

	clients := make([]*AzureHostedChatGPT, 0, len(endpoints))
	for endpoint, key := range endpoints {
		client := NewAIPChatGPT(
			modelName,
			WithEndpoint(endpoint),
			WithAzureAPIKey(key),
			WithAzureBaseClient(NewBaseClient(defaultOpts)),
		)
		clients = append(clients, client)
	}

	return clients, nil
}

func (a *AzureHostedChatGPT) BuildEndpointURL(endpoint string) string {
	return fmt.Sprintf("%s/chat/completions", endpoint)
}

// GetEncodingName returns the encoding name for ChatGPT models.
// TODO: we could use a different encoding for ChatGPT4 vs ChatGPT35Turbo.
func (a *AzureHostedChatGPT) GetEncodingName() string {
	return "cl100k_base"
}

func (a *AzureHostedChatGPT) Headers() map[string]string {
	return map[string]string{
		"api-key":      a.apiKey,
		"Content-Type": "application/json",
	}
}

func (a *AzureHostedChatGPT) GetModelName() string {
	return string(a.modelName)
}

func (a *AzureHostedChatGPT) GetModelGeneration() string {
	return a.modelGeneration
}

func (a *AzureHostedChatGPT) GetContextSize() int {
	return a.contextWindowSize
}

func (a *AzureHostedChatGPT) Hash() (string, error) {
	baseClientHash, err := a.BaseClient.Hash()
	if err != nil {
		return "", err
	}
	return fmt.Sprintf("%s-%s-%d-%s", baseClientHash, a.modelName, a.contextWindowSize, a.modelGeneration), nil
}
