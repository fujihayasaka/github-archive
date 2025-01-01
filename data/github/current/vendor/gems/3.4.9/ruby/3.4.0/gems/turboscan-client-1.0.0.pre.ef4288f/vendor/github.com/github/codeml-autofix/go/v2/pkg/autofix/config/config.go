// Package config contains the configuration options and initializers for the LLM clients.
package config

import (
	"context"
	"net/url"
	"os"

	llmConfig "github.com/github/code-scanning-ai-libraries/v2/llm/config"
	"github.com/github/code-scanning-ai-libraries/v2/llm/models"
	"github.com/github/code-scanning-ai-libraries/v2/st"
	"github.com/joho/godotenv" // simple env loading utility
)

// LoadEnv loads the .env file in development mode.
func LoadEnv() error {
	if os.Getenv("ENVIRONMENT") == "development" {
		if err := godotenv.Load(".env"); err != nil {
			return st.EnsureStackTracef(err, "error loading env file")
		}
	}
	return nil
}

// ConfigOption configures a Config via functional options.
// Config holds configuration settings for the autofix library.
// It manages API keys, endpoints, model settings, and runtime options.
// At minimum, one of CAPIProdKey, CAPIDevKey, or AzureOpenAIKey must be provided.
type ConfigOption func(*Config)

// Config holds all configuration for LLM clients
type Config struct {
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

	// Runtime Options
	DefaultCompletionOptions *models.CompletionOptions

	// Azure Configuration
	AzureOpenAIKey string `env:"AZURE_OPENAI_KEY" json:"azure_openai_key"`
	AzureModelKeys string `env:"AZURE_MODEL_KEYS" json:"azure_model_keys"`

	// Query Suite for rule validation
	QuerySuite string

	// Request Configuration
	UserAgent                    string
	StreamingEnabled             bool
	MockModelConversationLogPath string `env:"MOCK_MODEL_CONVERSATION_LOG_JSONL_PATH" json:"mock_model_conversation_log_path"`
}

// CAPI defaults
const (
	DefaultCAPIURL              = "https://api.githubcopilot.com"
	DefaultCAPIIntegrationID    = "ghas-code-scanning-autofix"
	DefaultCAPIIntegrationIDDev = "code-scanning-ai-dev"
	DefaultUserAgent            = "code scanning autofix"
	DefaultCacheDir             = ""
	DefaultCacheVersion         = ""
	DefaultAzureModelKeys       = ""
)

// NewConfig creates a config with options
func NewConfig(opts ...ConfigOption) *Config {
	cfg := &Config{
		CAPIURL:                      DefaultCAPIURL,
		CAPIIntegrationID:            DefaultCAPIIntegrationID,
		CAPIIntegrationIDDev:         DefaultCAPIIntegrationIDDev,
		UserAgent:                    DefaultUserAgent,
		DefaultCompletionOptions:     models.MkDefaultCompletionOptions(),
		CAPIDevKey:                   os.Getenv("CAPI_DEV_KEY"),
		CAPIProdKey:                  os.Getenv("CAPI_PROD_KEY"),
		AzureOpenAIKey:               os.Getenv("AZURE_OPENAI_KEY"),
		AzureModelKeys:               DefaultAzureModelKeys,
		StreamingEnabled:             false,
		MockModelConversationLogPath: "",
	}
	for _, opt := range opts {
		opt(cfg)
	}

	return cfg
}

// ConfigBuilder is a builder for Config
// Example: config.NewConfigBuilder(). WithAzureConfig("myAzureKey", "myAzureModels").WithTokenLimits(4000, 8192).Build()
type ConfigBuilder struct {
	config *Config
}

// NewConfigBuilder returns a ConfigBuilder initialized with default values.
func NewConfigBuilder() *ConfigBuilder {
	return &ConfigBuilder{
		config: &Config{
			CAPIURL:                      DefaultCAPIURL,
			CAPIIntegrationID:            DefaultCAPIIntegrationID,
			CAPIIntegrationIDDev:         DefaultCAPIIntegrationIDDev,
			UserAgent:                    DefaultUserAgent,
			DefaultCompletionOptions:     models.MkDefaultCompletionOptions(),
			CAPIDevKey:                   os.Getenv("CAPI_DEV_KEY"),
			CAPIProdKey:                  os.Getenv("CAPI_PROD_KEY"),
			AzureOpenAIKey:               os.Getenv("AZURE_OPENAI_KEY"),
			AzureModelKeys:               DefaultAzureModelKeys,
			StreamingEnabled:             false,
			MockModelConversationLogPath: "",
		},
	}
}

// WithAzureConfig adds Azure configuration.
func (b *ConfigBuilder) WithAzureConfig(key string, modelKeys string) *ConfigBuilder {
	b.config.AzureOpenAIKey = key
	b.config.AzureModelKeys = modelKeys
	return b
}

// WithProductionKey sets the production API key.
func (b *ConfigBuilder) WithProductionKey(key string) *ConfigBuilder {
	b.config.CAPIProdKey = key
	return b
}

// WithDevelopmentKey sets the development API key.
func (b *ConfigBuilder) WithDevelopmentKey(key string) *ConfigBuilder {
	b.config.CAPIDevKey = key
	return b
}

// WithCompletionOptions sets the default model completion options
func (b *ConfigBuilder) WithCompletionOptions(options *models.CompletionOptions) *ConfigBuilder {
	b.config.DefaultCompletionOptions = options
	return b
}

// Build validates and returns the Config.
func (b *ConfigBuilder) Build() (*Config, error) {
	if err := b.config.Validate(); err != nil {
		return nil, err
	}
	return b.config, nil
}

// Validate checks if config is valid.
func (c *Config) Validate() error {
	// Validate URL formats
	if c.CAPIURL != "" {
		if _, err := url.Parse(c.CAPIURL); err != nil {
			return st.EnsureStackTrace(err, "invalid CAPI URL")
		}
	}

	return nil
}

// ToModelConfig converts Config to llmConfig.ModelConfig, keeping the
// necessary fields for LLM client initialization.
func (c *Config) ToModelConfig() llmConfig.ModelConfig {
	return llmConfig.ModelConfig{
		AzureOpenAIKey:               c.AzureOpenAIKey,
		AzureModelKeys:               c.AzureModelKeys,
		CAPIProdKey:                  c.CAPIProdKey,
		CAPIDevKey:                   c.CAPIDevKey,
		CAPIURL:                      c.CAPIURL,
		CAPIIntegrationID:            c.CAPIIntegrationID,
		CAPIIntegrationIDDev:         c.CAPIIntegrationIDDev,
		MockModelConversationLogPath: c.MockModelConversationLogPath,
		DefaultCompletionOptions:     c.DefaultCompletionOptions,
	}
}

// WithEnvironment loads configuration from environment variables
func (b *ConfigBuilder) WithEnvironment() *ConfigBuilder {
	// Load environment variables into config
	b.config.CAPIDevKey = os.Getenv("CAPI_DEV_KEY")
	b.config.CAPIProdKey = os.Getenv("CAPI_PROD_KEY")
	b.config.AzureOpenAIKey = os.Getenv("AZURE_OPENAI_KEY")
	b.config.AzureModelKeys = os.Getenv("AZURE_MODEL_KEYS")
	b.config.CAPIURL = getEnvOrDefault("CAPI_URL", DefaultCAPIURL)
	b.config.MockModelConversationLogPath = os.Getenv("MOCK_MODEL_CONVERSATION_LOG_JSONL_PATH")

	return b
}

// Helper function for environment variables with defaults
func getEnvOrDefault(key, defaultValue string) string {
	value := os.Getenv(key)
	if value == "" {
		return defaultValue
	}
	return value
}

// contextKey type for context values
type contextKey string

// GitHubTokenKey is the context key for passing the GitHub token
const GitHubTokenKey contextKey = "github_token"

// GetGitHubToken returns the GitHub token from context (if present) falling
// back to the GH_TOKEN environment variable. It may return an empty string if
// no token is available.
func GetGitHubToken(ctx context.Context) string {
	// Extract the github token from the context if available
	githubToken, ok := ctx.Value(GitHubTokenKey).(string)
	if !ok || githubToken == "" {
		// Lets make one more attempt to get the token from the environment
		githubToken = os.Getenv("GH_TOKEN")
	}
	// At this point it can be set or it can be empty.
	return githubToken
}
