// Package config provides configuration settings for the LLM integration.
package config

import (
	"os"
	"strconv"
	"strings"

	"github.com/github/code-scanning-ai-libraries/v2/llm/models"
)

// ModelConfig holds configuration settings for the LLM system
type ModelConfig struct {
	// Azure Configuration
	AzureOpenAIKey string `env:"AZURE_OPENAI_KEY" json:"azure_openai_key"`
	AzureModelKeys string `env:"AZURE_MODEL_KEYS" json:"azure_model_keys"`

	// CAPIProdKey is the production API key for GitHub Copilot API
	CAPIProdKey string `env:"CAPI_PROD_KEY"`
	// CAPIDevKey is the development API key for GitHub Copilot API
	CAPIDevKey string `env:"CAPI_DEV_KEY"`

	// CAPIURL is the base URL for the GitHub Copilot API
	CAPIURL string `env:"CAPI_URL" json:"capi_url"`

	// CAPIIntegrationID is the integration ID for GitHub Copilot API
	// This is used to identify the integration in the CAPI.
	CAPIIntegrationID string
	// CAPIIntegrationIDDev is the integration ID for GitHub Copilot API in development mode
	// This is used to identify the integration in the CAPI.
	// This is used for testing and development purposes.
	CAPIIntegrationIDDev string

	// Mock model configuration
	MockModelConversationLogPath string `env:"MOCK_MODEL_CONVERSATION_LOG_JSONL_PATH" json:"mock_model_conversation_log_path"`

	// Runtime Options
	DefaultCompletionOptions *models.CompletionOptions

	// Retry indicates whether to automatically retry requests in case encountering retryable errors (e.g. a rate-limit)
	Retry bool

	// Used to send the `X-GitHub-User` header to relevant GH services, to indicate the user making the request
	GitHubUserID *int64
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
