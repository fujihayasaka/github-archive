// Package config provides configuration settings for the LLM integration.
package config

import (
	"os"
	"strconv"
	"strings"

	"github.com/github/code-scanning-ai-libraries/v4/llm/models"
)

// ModelConfig holds configuration settings for the LLM system
type ModelConfig struct {
	// Azure Configuration
	AzureOpenAIKey string `env:"AZURE_OPENAI_KEY" json:"azure_openai_key"`
	AzureModelKeys string `env:"AZURE_MODEL_KEYS" json:"azure_model_keys"`

	// CAPIProdKey is the production API key for GitHub Copilot API
	CAPIProdKey string `env:"CAPI_PROD_KEY" json:"capi_prod_key"`
	// CAPIDevKey is the development API key for GitHub Copilot API
	CAPIDevKey string `env:"CAPI_DEV_KEY" json:"capi_dev_key"`

	// CAPIURL is the base URL for the GitHub Copilot API
	CAPIURL string `env:"CAPI_URL" json:"capi_url"`

	// CAPIIntegrationID is the integration ID for GitHub Copilot API
	// This is used to identify the integration in the CAPI.
	CAPIIntegrationID string `json:"capi_integration_id,omitempty"`
	// CAPIIntegrationIDDev is the integration ID for GitHub Copilot API in development mode
	// This is used to identify the integration in the CAPI.
	// This is used for testing and development purposes.
	CAPIIntegrationIDDev string `json:"capi_integration_id_dev,omitempty"`
	// Mock model configuration
	MockModelConversationLogPath string `env:"MOCK_MODEL_CONVERSATION_LOG_JSONL_PATH" json:"mock_model_conversation_log_path"`

	// vLLM Configuration
	// VLLMBaseURL is the base URL for the vLLM deployment (e.g. "https://example-deployment.microsoft.com/amt/v1")
	VLLMBaseURL string `env:"VLLM_BASE_URL" json:"vllm_base_url"`
	// VLLMAPIKey is the optional API key for the vLLM deployment
	VLLMAPIKey string `env:"VLLM_API_KEY" json:"vllm_api_key"`
	// VLLMUseResponsesAPI determines whether to use the Responses API (true) or Chat Completions API (false)
	// Defaults to false if not set
	VLLMUseResponsesAPI *bool `env:"VLLM_USE_RESPONSES_API" json:"vllm_use_responses_api,omitempty"`

	// Runtime Options
	DefaultCompletionOptions *models.CompletionOptions `json:"default_completion_options,omitempty"`

	// Retry indicates whether to automatically retry requests in case encountering retryable errors (e.g. a rate-limit)
	Retry bool `json:"retry"`

	// Used to send the `X-GitHub-User` header to relevant GH services, to indicate the user making the request
	GitHubUserID *int64 `json:"github_user_id,omitempty"`
}

// NewConfig creates a config with options
func NewConfig() *ModelConfig {
	cfg := &ModelConfig{
		AzureOpenAIKey:               os.Getenv("AZURE_OPENAI_KEY"),
		AzureModelKeys:               os.Getenv("AZURE_MODEL_KEYS"),
		CAPIProdKey:                  os.Getenv("CAPI_PROD_KEY"),
		CAPIDevKey:                   os.Getenv("CAPI_DEV_KEY"),
		CAPIURL:                      os.Getenv("CAPI_URL"),
		CAPIIntegrationID:            os.Getenv("CAPI_INTEGRATION_ID"),
		CAPIIntegrationIDDev:         os.Getenv("CAPI_INTEGRATION_ID_DEV"),
		MockModelConversationLogPath: os.Getenv("MOCK_MODEL_CONVERSATION_LOG_JSONL_PATH"),
		VLLMBaseURL:                  os.Getenv("VLLM_BASE_URL"),
		VLLMAPIKey:                   os.Getenv("VLLM_API_KEY"),
		VLLMUseResponsesAPI:          getVLLMUseResponsesAPI(),
		GitHubUserID:                 getGitHubUserID(), // "GITHUB_USER_ID"
		DefaultCompletionOptions:     models.MkDefaultCompletionOptions(),
	}

	return cfg
}

func getGitHubUserID() *int64 {
	idStr := strings.TrimSpace(os.Getenv("GITHUB_USER_ID"))
	if idStr == "" {
		return nil
	}
	id, err := strconv.ParseInt(idStr, 10, 64)
	if err != nil {
		return nil
	}
	return &id
}

func getVLLMUseResponsesAPI() *bool {
	envVal := strings.TrimSpace(os.Getenv("VLLM_USE_RESPONSES_API"))
	if envVal == "" {
		return nil // Will default to false in the provider
	}
	val := strings.EqualFold(envVal, "true") || envVal == "1"
	return &val
}
