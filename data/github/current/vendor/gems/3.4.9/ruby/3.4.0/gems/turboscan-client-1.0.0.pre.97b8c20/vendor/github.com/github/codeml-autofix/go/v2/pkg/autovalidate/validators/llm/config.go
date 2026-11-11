package llm

import (
	"os"

	"github.com/github/code-scanning-ai-libraries/v2/st"
	"github.com/pkg/errors"
)

// Config holds the configuration settings for the LLM-based validator.
type Config struct {
	Model       string
	Temperature float64
	CAPIKey     string
	CachePath   string
	Retry       bool
}

// ConfigBuilder provides a builder pattern for constructing LLM validator configurations.
type ConfigBuilder struct {
	config *Config
}

// DefaultModel is the default LLM model used for validation when no model is specified.
// Note: When this is updated, remember to update the model used in production.
// See e.g. https://github.com/github/turboscan/pull/8756
const DefaultModel = "capi-dev-gpt-5-mini"

// DefaultTemperature is the default temperature value used for LLM completions.
const DefaultTemperature = 0.0

// NewConfigBuilder creates a new ConfigBuilder with default configuration values.
func NewConfigBuilder() *ConfigBuilder {
	return &ConfigBuilder{
		config: &Config{
			Model:       DefaultModel,
			Temperature: DefaultTemperature,
			CAPIKey:     "",
			CachePath:   "",
			Retry:       false,
		},
	}
}

// WithModel sets the model to use for LLM validation and returns the builder for chaining.
func (b *ConfigBuilder) WithModel(model string) *ConfigBuilder {
	b.config.Model = model
	return b
}

// WithTemperature sets the temperature for the model's completion options and returns the builder for chaining.
func (b *ConfigBuilder) WithTemperature(temperature float64) *ConfigBuilder {
	b.config.Temperature = temperature
	return b
}

// WithCAPIKey sets the CAPI key for authentication and returns the builder for chaining.
func (b *ConfigBuilder) WithCAPIKey(capiKey string) *ConfigBuilder {
	b.config.CAPIKey = capiKey
	return b
}

// WithCache sets the cache path for storing LLM responses and returns the builder for chaining.
func (b *ConfigBuilder) WithCache(cachePath string) *ConfigBuilder {
	b.config.CachePath = cachePath
	return b
}

// WithRetry sets whether to enable retry on LLM calls and returns the builder for chaining.
func (b *ConfigBuilder) WithRetry(retry bool) *ConfigBuilder {
	b.config.Retry = retry
	return b
}

// Build validates the configuration parameters and returns the final Config instance or an error if validation fails.
func (b *ConfigBuilder) Build() (*Config, error) {
	if b.config.Model == "" {
		return nil, errors.New("model cannot be empty")
	}

	if b.config.Temperature < 0 || b.config.Temperature > 1 {
		return nil, errors.New("temperature must be between 0 and 1")
	}

	if b.config.CachePath != "" {
		info, err := os.Stat(b.config.CachePath)
		if err != nil {
			if os.IsNotExist(err) {
				return nil, errors.Errorf("cache path does not exist: %s", b.config.CachePath)
			}
			return nil, st.EnsureStackTracef(err, "error checking cache path: %s", b.config.CachePath)
		}
		if !info.IsDir() {
			return nil, errors.Errorf("cache path is not a directory: %s", b.config.CachePath)
		}
	}

	return b.config, nil
}
