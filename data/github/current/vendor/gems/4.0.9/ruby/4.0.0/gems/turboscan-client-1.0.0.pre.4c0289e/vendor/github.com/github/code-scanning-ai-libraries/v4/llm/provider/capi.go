// Package provider provides a client for GitHub Copilot API (CAPI)
package provider

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"net/http"
	"regexp"
	"slices"
	"strings"
	"time"

	pkg_errors "github.com/pkg/errors"

	"github.com/github/code-scanning-ai-libraries/v4/enhancedctx"
	"github.com/github/code-scanning-ai-libraries/v4/errors"
	"github.com/github/code-scanning-ai-libraries/v4/llm/config"
	"github.com/github/code-scanning-ai-libraries/v4/llm/interactionmeta"
	"github.com/github/code-scanning-ai-libraries/v4/llm/models"

	capimodels "github.com/github/code-scanning-ai-libraries/v4/llm/provider/capi_models"

	"github.com/github/github-telemetry-go/kvp"
)

var (
	flavorPrefixRegex      = regexp.MustCompile(`^(dev|prod)-`)
	accessTokenPrefixRegex = regexp.MustCompile(`^(ghp_|github_pat_|gho_|ghu_|ghs_)`)
)

const (
	// DefaultIntegrationID is the default integration ID for production environments
	DefaultIntegrationID = "ghas-code-scanning-autofix"
	// DefaultIntegrationIDDev is the default integration ID for development environments
	DefaultIntegrationIDDev = "code-scanning-ai-dev"
)

// ClientOption defines a function that configures a CAPIClient
type ClientOption func(*CAPIClient)

// ModelRegistry defines the subset of registry functionality needed by the client.
// This allows injecting a mock for testing.
type ModelRegistry interface {
	GetModel(modelName string) (*capimodels.ModelEntry, bool)
}

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

// HMACProviderFunc returns a fresh Request-Hmac value for CAPI requests.
// Called on every request. Implementations may compute HMAC locally
// or fetch a one-time token from an external endpoint.
type HMACProviderFunc func() (string, error)

// WithHMACProvider allows injecting a custom HMAC provider.
// When set, this takes priority over the default apiKey-based HMAC generation.
func WithHMACProvider(fn HMACProviderFunc) ClientOption {
	return func(c *CAPIClient) {
		c.hmacProvider = fn
	}
}

// CAPIClient implements CAPI-specific functionality
type CAPIClient struct {
	defaultOptions  *models.CompletionOptions
	httpClient      HTTPClient
	registry        ModelRegistry
	integrationID   string
	modelName       string
	modelGeneration string
	baseURL         string
	apiKey          string
	hmacProvider    HMACProviderFunc
	modelEntry      *capimodels.ModelEntry
	flavor          string
	retry           bool
	ghUserID        *int64
}

// SessionRecorder is an interface for recording session chunks to the Sessions API
type SessionRecorder interface {
	Record(ctx context.Context, chunk any)
}

// registryHeaders returns the minimal headers required to call the model registry endpoint.
// and is also used as a basis for LLM requests.
func (c *CAPIClient) registryHeaders() map[string]string {
	headers := map[string]string{
		"Content-Type":           "application/json",
		"Copilot-Integration-Id": c.integrationID,
	}

	if isAccessToken(c.apiKey) {
		headers["Authorization"] = "Bearer " + c.apiKey
	} else if c.hmacProvider != nil {
		if hmacValue, err := c.hmacProvider(); err == nil {
			headers["Request-Hmac"] = hmacValue
		}
	}

	if c.ghUserID != nil {
		headers["X-GitHub-User"] = fmt.Sprintf("%d", *c.ghUserID)
	}

	return headers
}

// headers provides CAPI-specific HTTP headers
func (c *CAPIClient) headers(ctx context.Context) map[string]string {
	headers := c.registryHeaders()

	// Add request ID and GLB-Via headers for request tracking when passed in context and
	// we extract this from callback payload when calling agentic / callback autofind flow.
	if requestID := enhancedctx.GetRequestID(ctx); requestID != "" {
		headers["X-GitHub-Request-Id"] = requestID
		// Needed so GLB doesn't strip the request ID header
		headers["X-GLB-Via"] = "true"
	}

	if meta, ok := interactionmeta.CAPIInteractionMetaFromContext(ctx); ok {
		if meta.ID != "" {
			headers[interactionmeta.InteractionIDHeader] = meta.ID
		}
		if meta.Type != "" {
			headers[interactionmeta.InteractionTypeHeader] = meta.Type
		}
	}
	// - first call: use initiator from callback payload (CCRA chooses whether to pass "user" or "agent")
	//   if empty, fall back to "agent"
	// - subsequent calls: always sets to "agent"
	if interactionmeta.IsFirstCall(ctx) {
		initiator := "agent" // default fallback
		if meta, ok := interactionmeta.CAPIInteractionMetaFromContext(ctx); ok && meta.Initiator != "" {
			initiator = meta.Initiator
		}
		headers[interactionmeta.InitiatorHeader] = initiator

		logFields := []kvp.Field{kvp.String("initiator", initiator)}
		if requestID := enhancedctx.GetRequestID(ctx); requestID != "" {
			logFields = append(logFields, kvp.String("request_id", requestID))
		}
		enhancedctx.Logger(ctx).Info("Setting initiator for first call", logFields...)
	} else {
		headers[interactionmeta.InitiatorHeader] = "agent"

		logFields := []kvp.Field{kvp.String("initiator", "agent")}
		if requestID := enhancedctx.GetRequestID(ctx); requestID != "" {
			logFields = append(logFields, kvp.String("request_id", requestID))
		}
		enhancedctx.Logger(ctx).Info("Setting initiator for subsequent call", logFields...)
	}

	return headers
}

// NewCapiClient creates a new CAPI client with the specified flavor and configuration
func NewCapiClient(
	ctx context.Context,
	flavor string, // capi-dev-<name> or capi-prod-<name>
	retry bool, // whether to enable retry logic
	cfg *config.ModelConfig,
	options ...ClientOption,
) (*CAPIClient, error) {
	// Create with defaults
	client := &CAPIClient{ //nolint:exhaustruct // not all fields are initialized here, set later
		baseURL:  capimodels.DefaultCapiURL,
		flavor:   flavor,
		retry:    retry,
		ghUserID: cfg.GitHubUserID,
	}

	// Apply options
	for _, option := range options {
		option(client)
	}

	// Set required fields from config if not provided via options
	if client.apiKey == "" {
		isProd := strings.HasPrefix(flavor, "prod")
		if isProd {
			client.apiKey = cfg.CAPIProdKey
		} else {
			client.apiKey = cfg.CAPIDevKey
		}
	}

	// If cfg.CAPIURL is provided, override the default baseURL.
	// This allows customization of the API endpoint, e.g., for Proxima stamps.
	if cfg.CAPIURL != "" {
		client.baseURL = cfg.CAPIURL
	}

	if client.apiKey == "" && client.hmacProvider == nil {
		return nil, pkg_errors.Errorf("no Copilot API key or HMAC provider configured for %s", flavor)
	}

	// Default HMAC provider: compute locally from apiKey
	if client.hmacProvider == nil && !isAccessToken(client.apiKey) {
		apiKey := client.apiKey
		client.hmacProvider = func() (string, error) {
			return generateHMAC(apiKey), nil
		}
	}

	// Initialize default options if not provided
	if client.defaultOptions == nil {
		client.defaultOptions = cfg.DefaultCompletionOptions
	}

	// Initialize HTTP client if not provided
	if client.httpClient == nil {
		client.httpClient = &http.Client{Timeout: 10 * time.Minute} //nolint:exhaustruct // No need for all fields
	}

	// Set integrationID if not provided
	if client.integrationID == "" {
		isProd := strings.HasPrefix(flavor, "prod")
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

	// Get model entry - if not provided in options
	if client.modelEntry == nil {
		var registry ModelRegistry

		// Use injected registry if available, otherwise get default registry
		if client.registry != nil {
			registry = client.registry
		} else {
			var err errors.LLMError
			registry, err = capimodels.GetRegistry(ctx, client.baseURL, client.registryHeaders())
			if err != nil {
				return nil, pkg_errors.Wrap(err, "failed to initialize model registry")
			}
		}

		if client.modelName == "" {
			// Get model name first
			client.modelName = getModelName(flavor)
		}

		// Try to find capabilities in the registry
		model, found := registry.GetModel(client.modelName)
		if !found {
			return nil, pkg_errors.Errorf("model %s not found in registry. Ensure the Copilot /models endpoint includes it", client.modelName)
		}
		client.modelEntry = model
	}
	// Always ensure limits are set
	ensureCapabilitiesLimits(client.modelEntry.Capabilities)

	// Set model generation
	client.modelGeneration = client.modelEntry.Capabilities.Family

	return client, nil
}

// ensureCapabilitiesLimits makes sure the capabilities has Limits initialized
func ensureCapabilitiesLimits(caps *capimodels.ModelCapabilities) {
	if caps == nil {
		return
	}

	if caps.Limits == nil {
		caps.Limits = &capimodels.ModelLimits{ //nolint:exhaustruct // only setting defaults, other fields are optional
			MaxContextWindowTokens: 128000,
			MaxOutputTokens:        4096,
			MaxPromptTokens:        64000,
		}
	}
}

// GetModelName returns the name of the model used by this client
func (c *CAPIClient) GetModelName() string {
	return c.modelName
}

// GetProviderName returns the integration name for this client
func (c *CAPIClient) GetProviderName() string {
	return "CAPI"
}

func getModelName(flavor string) string {
	// Strip the dev- or prod- prefix from the flavor
	modelName := flavorPrefixRegex.ReplaceAllString(flavor, "")

	// for backwards compatibility, support some aliases we've used in the past.
	switch modelName {
	case "4o":
		modelName = "gpt-4o"
	case "4o-mini":
		modelName = "gpt-4o-mini"
	case "4.1":
		modelName = "gpt-4.1"
	}

	return modelName
}

// Complete sends an LLM completion request with tools support
// If the model responds with tool calls, this will:
// 1. Execute each requested tool
// 2. Add the tool responses to the messages
// 3. Recursively call the API with the updated messages until no more tool calls are requested
func (c *CAPIClient) Complete(ctx context.Context, messages []models.ChatMessage, tools []models.Tool, options *models.CompletionOptions) (string, []models.ChatMessage, *models.TokenUsage, errors.LLMError) { //nolint:maintidx // Yes, this function is complex.
	ctx, span := enhancedctx.StartSpan(ctx, "llm.CAPIClient.Complete")
	defer span.End()

	if ctx.Err() != nil {
		return "", nil, nil, errors.NewErrorFromContextErr(ctx, "context canceled before request started")
	}

	logger := enhancedctx.Logger(ctx)

	// Determine endpoint support from model metadata.
	// If SupportedEndpoints is nil, assume Chat Completions is available.
	doesntSupportChatCompletions := c.modelEntry.SupportedEndpoints != nil &&
		!slices.Contains(*c.modelEntry.SupportedEndpoints, "/chat/completions")
	supportsResponses := c.modelEntry.SupportedEndpoints != nil &&
		slices.Contains(*c.modelEntry.SupportedEndpoints, "/responses")

	// Use the Responses API when:
	// 1. The model doesn't support Chat Completions but does support the Responses API, OR
	// 2. The request uses features that require the Responses API (tools or verbosity) and the model supports it.
	useResponsesAPI := (doesntSupportChatCompletions && supportsResponses) ||
		((len(tools) > 0 || (options != nil && options.Verbosity != "")) && supportsResponses)

	if useResponsesAPI {
		if options == nil {
			options = &models.CompletionOptions{}
		}

		logger.Info("Making CAPI responses request", []kvp.Field{
			kvp.String("model", c.modelName),
			kvp.Int("message_count", len(messages)),
			kvp.Int("tools_count", len(tools)),
			kvp.Any("options", options.ToResponsesMap(ctx)),
		}...)

		client := &ResponsesAPIClient{
			fullEndpoint: c.baseURL + "/responses",
			modelName:    c.GetModelName(),
			providerName: c.GetProviderName(),
			retry:        c.retry,
			headersFn:    func(ctx context.Context) map[string]string { return c.headers(ctx) },
			httpClient:   c.httpClient,
		}
		return client.Complete(ctx, messages, tools, options)
	}

	return c.doChatCompletionsCall(ctx, messages, tools, options)
}

func (c *CAPIClient) doChatCompletionsCall(ctx context.Context, messages []models.ChatMessage, tools []models.Tool, options *models.CompletionOptions) (string, []models.ChatMessage, *models.TokenUsage, errors.LLMError) { //nolint:maintidx // Yes, this function is complex.
	logger := enhancedctx.Logger(ctx)

	if options == nil {
		options = &models.CompletionOptions{}
	}

	// Clone the options to avoid modifying the original
	// Based on the models capabilities, we may set for example, the stream option to false.
	options = options.Clone()

	// If the user did not specify a streaming preference, we default to true.
	var shouldStream bool
	if options.Stream != nil {
		// set to user preference
		shouldStream = *options.Stream
	} else {
		shouldStream = true
	}

	// Disable streaming if the model doesn't support it.
	// Additionally, CAPI does not support streaming with tool calls.
	if !c.modelEntry.Capabilities.Supports.Streaming || len(tools) > 0 {
		shouldStream = false
	}

	options.Stream = &shouldStream

	logger.Info("Making CAPI chat request", []kvp.Field{
		kvp.String("model", c.modelName),
		kvp.Bool("stream", shouldStream),
		kvp.Int("message_count", len(messages)),
		kvp.Any("options", options.ToChatCompletionsMap(ctx)),
	}...)

	client := NewChatCompletionsAPIClient(
		c.baseURL+"/chat/completions",
		c.GetProviderName(),
		c.GetModelName(),
		c.retry,
		c.defaultOptions,
		WithHTTPClient(c.httpClient),
	).WithHeadersFn(func(ctx context.Context) map[string]string { return c.headers(ctx) }).
		WithCacheControl()

	resp, transcript, usage, llmErr := client.Complete(ctx, messages, tools, options)
	if llmErr != nil {
		logger.Error("API request failed", []kvp.Field{
			kvp.String("error_type", llmErr.Type()),
			kvp.String("error_message", llmErr.Error()),
			kvp.Bool("retryable", llmErr.Retryable()),
		}...)
		return "", nil, nil, llmErr
	}

	if usage != nil {
		logger.Info("API request succeeded", []kvp.Field{
			kvp.Int("new_messages", len(transcript)-len(messages)),
			kvp.Int("prompt_tokens", usage.PromptTokens),
			kvp.Int("completion_tokens", usage.CompletionTokens),
			kvp.Int("total_tokens", usage.TotalTokens),
		}...)
	}

	return resp, transcript, usage, nil
}

func isAccessToken(key string) bool {
	return accessTokenPrefixRegex.MatchString(key)
}

func generateHMAC(apiKey string) string {
	current := time.Now().Unix()
	h := hmac.New(sha256.New, []byte(apiKey))
	_, _ = fmt.Fprintf(h, "%d", current)
	hmacValue := hex.EncodeToString(h.Sum(nil))
	return fmt.Sprintf("%d.%s", current, hmacValue)
}
