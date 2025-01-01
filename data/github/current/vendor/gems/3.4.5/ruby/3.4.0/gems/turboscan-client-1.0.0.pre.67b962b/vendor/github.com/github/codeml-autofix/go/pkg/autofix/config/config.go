// Package config contains the configuration options and initializers for the LLM clients.
package config

import (
	"fmt"
	"net/url"
	"os"

	"github.com/github/codeml-autofix/go/pkg/autofix/llm/models"
	"github.com/joho/godotenv" // simple env loading utility
)

// LoadEnv loads the .env file in development mode.
func LoadEnv() error {
	if os.Getenv("ENVIRONMENT") == "development" {
		if err := godotenv.Load(".env"); err != nil {
			return fmt.Errorf("error loading env file: %w", err)
		}
	}
	return nil
}

// WithDevelopmentMode sets the development mode for the configuration.
// In development mode, the dev API keys and endpoints will be used.
func (b *ConfigBuilder) WithDevelopmentMode(devMode bool) *ConfigBuilder {
	// If in dev mode, ensure we're using dev integration ID
	if devMode {
		// Set development integration ID for CAPI
		b.config.CAPIIntegrationID = b.config.CAPIIntegrationIDDev
	}
	return b
}

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
	CAPIURL string `json:"capi_url" env:"CAPI_URL"`
	// EndpointURL is the base URL for the endpoint
	EndpointURL string `json:"endpoint_url" env:"ENDPOINT_URL"`

	// CAPIIntegrationID is the integration ID for GitHub Copilot API
	// This is used to identify the integration in the CAPI.
	CAPIIntegrationID string
	// CAPIIntegrationIDDev is the integration ID for GitHub Copilot API in development mode
	// This is used to identify the integration in the CAPI.
	// This is used for testing and development purposes.
	CAPIIntegrationIDDev string

	// ModelName is the option or flag passed to the Autofix CLI tooling to generate fix.
	ModelName string `json:"model_name" env:"AUTOFIX_MODEL"`
	// CAPIModelName is the model name for the GitHub Copilot API
	// This is used to identify the model in the CAPI.
	CAPIModelName string `json:"capi_model_name" env:"CAPI_MODEL_NAME"`

	// Runtime Options
	DefaultCompletionOptions *models.CompletionOptions
	// RootPath is needed so that we can index various files that were previously located
	// inside of the `cocofix/` directory. `cocofix.js` was using its own source directory
	// as the root path, which was safe for it because it was always running from the same
	// directory. We can't do that here because the Go code is running as a binary in an
	// arbitrary location. So we need to pass in the root path as a command line argument.
	RootPath string `json:"root_path" env:"ROOT_PATH"`

	// Azure Configuration
	AzureOpenAIKey string `json:"azure_openai_key" env:"AZURE_OPENAI_KEY"`
	AzureModelKeys string `json:"azure_model_keys" env:"AZURE_MODEL_KEYS"`

	// Token Limits
	MaxPromptTokens        int
	MaxContextWindowTokens int

	// Request Configuration
	UserAgent                    string
	StreamingEnabled             bool
	MockModelConversationLogPath string `json:"mock_model_conversation_log_path" env:"MOCK_MODEL_CONVERSATION_LOG_JSONL_PATH"`
}

// CAPI defaults
const (
	DefaultCAPIURL              = "https://api.githubcopilot.com"
	DefaultCAPIIntegrationID    = "ghas-code-scanning-autofix"
	DefaultCAPIIntegrationIDDev = "ghas-code-scanning-autofix-dev"
	DefaultCAPI4OName           = "gpt-4o"
	DefaultCAPI4ONameMini       = "gpt-4o-mini"
	DefaultCAPIO1Name           = "o1"
	DefaultCAPIO3Name           = "o3"
	DefaultCAPIO1NameMini       = "o1-mini"
	DefaultCAPIO4MiniName       = "o4-mini"
	DefaultCAPIClaudeSonnet     = "claude-3.5-sonnet"
	DefaultCAPIGeminiPro        = "gemini-1.5-pro"
	DefaultUserAgent            = "code scanning autofix"
	DefaultMaxPromptTokens      = 4000
	DefaultMaxContextTokens     = 8192
	DefaultEndpointURL          = ""
	DefaultModelName            = ""
	DefaultCAPIModelName        = ""
	DefaultCacheDir             = ""
	DefaultCacheVersion         = ""
	DefaultAzureModelKeys       = ""
)

func NewDefaultCompletionsOptions() *models.CompletionOptions {
	return &models.CompletionOptions{ //nolint:exhaustruct
		MaxTokens:   1024,
		Temperature: 0.7,
	}
}

// NewConfig creates a config with options
func NewConfig(opts ...ConfigOption) *Config {
	defaults := NewDefaultCompletionsOptions()
	cfg := &Config{
		CAPIURL:                      DefaultCAPIURL,
		CAPIIntegrationID:            DefaultCAPIIntegrationID,
		CAPIIntegrationIDDev:         DefaultCAPIIntegrationIDDev,
		UserAgent:                    DefaultUserAgent,
		MaxPromptTokens:              DefaultMaxPromptTokens,
		MaxContextWindowTokens:       DefaultMaxContextTokens,
		DefaultCompletionOptions:     defaults,
		CAPIDevKey:                   os.Getenv("CAPI_DEV_KEY"),
		CAPIProdKey:                  os.Getenv("CAPI_PROD_KEY"),
		AzureOpenAIKey:               os.Getenv("AZURE_OPENAI_KEY"),
		EndpointURL:                  DefaultEndpointURL,
		ModelName:                    DefaultModelName,
		CAPIModelName:                DefaultCAPIModelName,
		AzureModelKeys:               DefaultAzureModelKeys,
		StreamingEnabled:             false,
		MockModelConversationLogPath: "",
		RootPath:                     "../../cocofix/",
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
	defaults := NewDefaultCompletionsOptions()
	return &ConfigBuilder{
		config: &Config{
			CAPIURL:                      DefaultCAPIURL,
			CAPIIntegrationID:            DefaultCAPIIntegrationID,
			CAPIIntegrationIDDev:         DefaultCAPIIntegrationIDDev,
			UserAgent:                    DefaultUserAgent,
			MaxPromptTokens:              DefaultMaxPromptTokens,
			MaxContextWindowTokens:       DefaultMaxContextTokens,
			DefaultCompletionOptions:     defaults,
			CAPIDevKey:                   os.Getenv("CAPI_DEV_KEY"),
			CAPIProdKey:                  os.Getenv("CAPI_PROD_KEY"),
			AzureOpenAIKey:               os.Getenv("AZURE_OPENAI_KEY"),
			EndpointURL:                  DefaultEndpointURL,
			ModelName:                    DefaultModelName,
			CAPIModelName:                DefaultCAPIModelName,
			AzureModelKeys:               DefaultAzureModelKeys,
			StreamingEnabled:             false,
			MockModelConversationLogPath: "",
			RootPath:                     "../../cocofix/",
		},
	}
}

// WithAzureConfig adds Azure configuration.
func (b *ConfigBuilder) WithAzureConfig(key string, modelKeys string) *ConfigBuilder {
	b.config.AzureOpenAIKey = key
	b.config.AzureModelKeys = modelKeys
	return b
}

// WithTokenLimits sets the prompt and context token limits.
func (b *ConfigBuilder) WithTokenLimits(promptTokens, contextTokens int) *ConfigBuilder {
	b.config.MaxPromptTokens = promptTokens
	b.config.MaxContextWindowTokens = contextTokens
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

// WithModel sets the model name to use for suggestions
func (b *ConfigBuilder) WithModel(modelName string) *ConfigBuilder {
	b.config.ModelName = modelName
	return b
}

// WithCompletionOptions sets the default model completion options
func (b *ConfigBuilder) WithCompletionOptions(options *models.CompletionOptions) *ConfigBuilder {
	b.config.DefaultCompletionOptions = options
	return b
}

// WithRootPath sets the root path for locating resource files
func (b *ConfigBuilder) WithRootPath(path string) *ConfigBuilder {
	b.config.RootPath = path
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
			return fmt.Errorf("invalid CAPI URL: %w", err)
		}
	}

	return nil
}

// WithEnvironment loads configuration from environment variables
func (b *ConfigBuilder) WithEnvironment() *ConfigBuilder {
	// Load environment variables into config
	b.config.CAPIDevKey = os.Getenv("CAPI_DEV_KEY")
	b.config.CAPIProdKey = os.Getenv("CAPI_PROD_KEY")
	b.config.AzureOpenAIKey = os.Getenv("AZURE_OPENAI_KEY")
	b.config.CAPIURL = getEnvOrDefault("CAPI_URL", DefaultCAPIURL)
	b.config.EndpointURL = getEnvOrDefault("ENDPOINT_URL", DefaultEndpointURL)
	b.config.ModelName = getEnvOrDefault("AUTOFIX_MODEL", DefaultModelName)
	b.config.CAPIModelName = getEnvOrDefault("CAPI_MODEL_NAME", DefaultCAPIModelName)
	b.config.RootPath = getEnvOrDefault("ROOT_PATH", b.config.RootPath)
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
