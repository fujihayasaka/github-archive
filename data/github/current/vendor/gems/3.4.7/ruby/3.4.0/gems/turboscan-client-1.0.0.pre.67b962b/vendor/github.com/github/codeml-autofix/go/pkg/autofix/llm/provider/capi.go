// client for GitHub Copilot API (CAPI)
// This client handles the interaction with the CAPI, including request
package provider

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"strings"
	"time"

	"github.com/github/codeml-autofix/go/pkg/autofix"
	"github.com/github/codeml-autofix/go/pkg/autofix/config"
	"github.com/github/codeml-autofix/go/pkg/autofix/enhancedctx"
	"github.com/github/codeml-autofix/go/pkg/autofix/llm/models"
)

// ModelFlavor represents the different types of CAPI models
type ModelFlavor string

const (
	Prod4O          ModelFlavor = "prod-4o"
	Dev4O           ModelFlavor = "dev-4o"
	Dev41           ModelFlavor = "dev-4.1"
	Dev4OMini       ModelFlavor = "dev-4o-mini"
	DevO1           ModelFlavor = "dev-o1"
	DevO3           ModelFlavor = "dev-o3"
	ProdO3          ModelFlavor = "prod-o3"
	DevO1Mini       ModelFlavor = "dev-o1-mini"
	DevO4Mini       ModelFlavor = "dev-o4-mini"
	DevClaudeSonnet ModelFlavor = "dev-claude-3.5-sonnet"
	DevGeminiPro    ModelFlavor = "dev-gemini-1.5-pro"

	// Default URLs and IDs
	DefaultCapiURL          = "https://api.githubcopilot.com"
	DefaultIntegrationID    = "ghas-code-scanning-autofix"
	DefaultIntegrationIDDev = "ghas-code-scanning-autofix-dev"

	// Model names
	ModelGPT4O        = "gpt-4o"
	ModelGPT4OMini    = "gpt-4o-mini"
	ModelGPT41        = "gpt-4.1"
	ModelO1           = "o1"
	ModelO3           = "o3"
	ModelO4Mini       = "o4-mini"
	ModelO1Mini       = "o1-mini"
	ModelClaudeSonnet = "claude-3.5-sonnet"
	ModelGeminiPro    = "gemini-1.5-pro"
)

// ClientOption defines a function that configures a CAPIClient
type ClientOption func(*CAPIClient)

// WithRegistry allows injecting a model registry
func WithRegistry(registry ModelRegistry) ClientOption {
	return func(c *CAPIClient) {
		c.registry = registry
	}
}

// WithIntegrationID allows setting a custom integration ID
func WithIntegrationID(integrationID string) ClientOption {
	return func(c *CAPIClient) {
		c.integrationID = integrationID
	}
}

// WithURL allows injecting an API URL
func WithURL(url string) ClientOption {
	return func(c *CAPIClient) {
		c.baseURL = url
	}
}

// WithAPIKey allows setting a custom API key
func WithAPIKey(apiKey string) ClientOption {
	return func(c *CAPIClient) {
		c.apiKey = apiKey
	}
}

// WithModelName allows setting a custom model name
func WithModelName(modelName string) ClientOption {
	return func(c *CAPIClient) {
		c.modelName = modelName
	}
}

// WithModelCapabilities allows setting custom model capabilities
func WithModelCapabilities(capabilities *models.ModelCapabilities) ClientOption {
	return func(c *CAPIClient) {
		c.capabilities = capabilities
	}
}

// CAPIClient implements CAPI-specific functionality
type CAPIClient struct {
	*BaseClient
	registry        ModelRegistry
	integrationID   string
	modelName       string
	modelGeneration string
	baseURL         string
	apiKey          string
	capabilities    *models.ModelCapabilities
	flavor          ModelFlavor
}

// Headers provides CAPI-specific HTTP headers
func (c *CAPIClient) Headers() map[string]string {
	headers := map[string]string{
		"Content-Type":           "application/json",
		"Copilot-Integration-Id": c.integrationID,
	}

	current := time.Now().Unix()
	h := hmac.New(sha256.New, []byte(c.apiKey))
	h.Write([]byte(fmt.Sprintf("%d", current)))
	hmacValue := hex.EncodeToString(h.Sum(nil))
	headers["Request-Hmac"] = fmt.Sprintf("%d.%s", current, hmacValue)
	return headers
}

// BuildEndpointURL builds the full URL for CAPI endpoints
func (c *CAPIClient) BuildEndpointURL(endpoint string) string {
	if strings.HasSuffix(c.baseURL, "/") {
		return c.baseURL + strings.TrimPrefix(endpoint, "/")
	}
	return c.baseURL + endpoint
}

func NewClient(
	flavor ModelFlavor,
	cfg *config.Config,
	options ...ClientOption,
) (*CAPIClient, autofix.AutofixError) {
	// Create with defaults
	client := &CAPIClient{ //nolint:exhaustruct
		baseURL: DefaultCapiURL,
		flavor:  flavor,
	}

	// Apply options
	for _, option := range options {
		option(client)
	}

	// Set required fields from config if not provided via options
	if client.apiKey == "" {
		isProd := strings.HasPrefix(string(flavor), "prod")
		if isProd {
			client.apiKey = cfg.CAPIProdKey
		} else {
			client.apiKey = cfg.CAPIDevKey
		}
	}

	if client.apiKey == "" {
		return nil, autofix.NewInvalidRequestError(fmt.Sprintf("no Copilot API key provided for %s", flavor))
	}

	// Initialize baseClient if not provided
	if client.BaseClient == nil {
		client.BaseClient = NewBaseClient(&models.DefaultCompletionOptions)
	}

	// Get model capabilities - if not provided in options
	if client.capabilities == nil {
		registry, err := models.GetRegistry()
		if err != nil {
			return nil, autofix.NewLogicError(fmt.Sprintf("failed to initialize model registry: %v", err))
		}

		// Get model name first
		modelName := getModelName(flavor, cfg.ModelName)
		client.modelName = modelName

		// Try to find capabilities in the registry
		model, found := registry.GetModel(modelName)
		if !found {
			return nil, autofix.NewLogicError(fmt.Sprintf("model %s not found in registry. Ensure models.json is up-to-date (see capiModelConstants.ts)", modelName))
		}
		client.capabilities = model.Capabilities
	}
	// Always ensure limits are set
	ensureCapabilitiesLimits(client.capabilities)

	// Set model generation
	client.modelGeneration = client.capabilities.Family

	// Set integrationID if not provided
	if client.integrationID == "" {
		isProd := strings.HasPrefix(string(flavor), "prod")
		if isProd {
			client.integrationID = cfg.CAPIIntegrationID
			if client.integrationID == "" {
				client.integrationID = DefaultIntegrationID
			}
		} else {
			client.integrationID = cfg.CAPIIntegrationIDDev
			if client.integrationID == "" {
				client.integrationID = DefaultIntegrationIDDev
			}
		}
	}

	return client, nil

}

// ensureCapabilitiesLimits makes sure the capabilities has Limits initialized
func ensureCapabilitiesLimits(caps *models.ModelCapabilities) {
	if caps == nil {
		return
	}

	if caps.Limits == nil {
		caps.Limits = &models.ModelLimits{ //nolint:exhaustruct
			MaxContextWindowTokens: 128000,
			MaxOutputTokens:        4096,
			MaxPromptTokens:        64000,
		}
	}
}

func (c *CAPIClient) GetModelName() string {
	return c.modelName
}

func (c *CAPIClient) GetModelGeneration() string {
	return c.modelGeneration
}

func (c *CAPIClient) GetContextSize() int {
	return c.capabilities.Limits.MaxContextWindowTokens
}

func (c *CAPIClient) GetDefaultCompletionOptions() models.CompletionOptions {
	if c.BaseClient == nil || c.BaseClient.defaultOptions == nil {
		// Return safe defaults if not initialized
		return models.CompletionOptions{ //nolint:exhaustruct
			Temperature: 0.1,
			Stream:      true,
			MaxTokens:   4000,
		}
	}
	return *c.BaseClient.defaultOptions.Clone()
}

func (c *CAPIClient) GetMaxTokens() int {
	return c.GetDefaultCompletionOptions().MaxTokens
}

func getModelName(flavor ModelFlavor, configModelName string) string {
	if configModelName != "" {
		return configModelName
	}

	switch flavor {
	case Prod4O, Dev4O:
		return ModelGPT4O
	case Dev4OMini:
		return ModelGPT4OMini
	case Dev41:
		return ModelGPT41
	case DevO1:
		return ModelO1
	case DevO1Mini:
		return ModelO1Mini
	case DevClaudeSonnet:
		return ModelClaudeSonnet
	case DevGeminiPro:
		return ModelGeminiPro
	case DevO3, ProdO3:
		return ModelO3
	case DevO4Mini:
		return ModelO4Mini
	default:
		return ModelGPT4O
	}
}

func (c *CAPIClient) ValidateRequest(messages []models.ChatMessage) autofix.AutofixError {
	if len(messages) == 0 {
		return autofix.NewInvalidRequestError("no messages provided")
	}
	if messages[len(messages)-1].Role != models.ChatMessageRoleUser {
		return autofix.NewInvalidRequestError("last message must be from user")
	}
	return nil
}

func (c *CAPIClient) Complete(ctx context.Context, messages []models.ChatMessage) (string, autofix.AutofixError) {
	ctx, span := enhancedctx.StartSpan(ctx, "llm.CAPIClient.Complete")
	defer span.End()

	opts := c.GetDefaultCompletionOptions()
	return c.CompleteWithOptions(ctx, messages, &opts)
}

func (c *CAPIClient) CompleteWithOptions(ctx context.Context, messages []models.ChatMessage, options *models.CompletionOptions) (string, autofix.AutofixError) {
	ctx, span := enhancedctx.StartSpan(ctx, "llm.CAPIClient.CompleteWithOptions")
	defer span.End()

	// Add defensive checks at the start of the method
	if c == nil {
		return "", autofix.NewInvalidRequestError("CAPIClient is nil")
	}

	if c.apiKey == "" {
		return "", autofix.NewInvalidRequestError("API key not configured for CAPI client")
	}

	if err := c.ValidateRequest(messages); err != nil {
		return "", err
	}

	if c.capabilities.Limits == nil {
		return "", autofix.NewLogicError("model capabilities not loaded")
	}

	if options == nil {
		return "", autofix.NewInvalidRequestError("options cannot be nil")
	}

	if numTokens := models.NumTokensInChat(messages, c); numTokens > c.capabilities.Limits.MaxPromptTokens {
		return "", autofix.NewInvalidRequestError(
			fmt.Sprintf("prompt exceeds token limit (%d > %d)",
				numTokens, c.capabilities.Limits.MaxPromptTokens))
	}

	maxTokens, err := models.ComputeMaxTokens(messages, c)
	if err != nil {
		return "", autofix.NewLogicError(fmt.Sprintf("computing max tokens: %v", err))
	}

	var optionsClone *models.CompletionOptions
	if options == nil {
		defaultOpts := c.GetDefaultCompletionOptions()
		optionsClone = &defaultOpts
	} else {
		// Clone the options to avoid modifying the original
		// Based on the models capabilities, we may set for example, the stream option to false.
		optionsClone = options.Clone()
	}

	if !c.capabilities.Supports.Streaming {
		optionsClone.Stream = false
	}

	reqBody := map[string]interface{}{
		"model":       c.modelName,
		"messages":    messages,
		"max_tokens":  maxTokens,
		"temperature": optionsClone.Temperature,
		"stream":      optionsClone.Stream,
	}

	if optionsClone.Stream {
		reqBody["stream_options"] = map[string]interface{}{
			"include_usage": true,
		}
	}

	resp, err := c.BaseClient.doRequest(ctx, c, "/chat/completions", reqBody, optionsClone.Stream)
	if err != nil {
		return "", autofix.NewRetryableError(
			fmt.Sprintf("CAPI request failed: %v", err),
			time.Second*5)
	}

	return resp, nil
}

func (c *CAPIClient) GetEncodingName() string {
	if c.capabilities == nil {
		return "cl100k_base"
	}
	if c.capabilities.Tokenizer == "" {
		return "cl100k_base"
	}
	return c.capabilities.Tokenizer
}

func (c *CAPIClient) Hash() (string, error) {
	capabilitiesHash, err := c.capabilities.Hash()
	if err != nil {
		return "", fmt.Errorf("failed to compute capabilities hash: %w", err)
	}

	return fmt.Sprintf("%s-%s-%s-%s-%s-%s",
		c.integrationID,
		c.modelName,
		c.modelGeneration,
		c.baseURL,
		capabilitiesHash,
		c.flavor,
	), nil
}
