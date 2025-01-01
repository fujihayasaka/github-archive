package autovalidate

import (
	"os"

	"github.com/github/code-scanning-ai-libraries/v2/st"
	"github.com/pkg/errors"
)

// Config holds settings controlling the autovalidation model invocation.
type Config struct {
	Model       string
	Temperature float64
	CAPIKey     string
	CachePath   string
	retry       bool
}

// ConfigBuilder constructs a Config using fluent option methods with
// validation performed in Build.
type ConfigBuilder struct {
	config *Config
}

// DefaultModel represents the default model used for autovalidation.
//
// note: when this is updated in our codebase, remember to update the model used by
// turboscan in production. See e.g. https://github.com/github/turboscan/pull/8756
const DefaultModel = "capi-dev-o4-mini"

// DefaultTemperature is the default sampling temperature for the model.
const DefaultTemperature = 0.0

// NewConfigBuilder initializes a ConfigBuilder with default values.
func NewConfigBuilder() *ConfigBuilder {
	return &ConfigBuilder{
		config: &Config{
			Model:       DefaultModel,
			Temperature: DefaultTemperature,
			CAPIKey:     "",
			CachePath:   "",
			retry:       false,
		},
	}
}

// WithModel sets the model identifier.
func (b *ConfigBuilder) WithModel(model string) *ConfigBuilder {
	b.config.Model = model
	return b
}

// WithTemperature sets the sampling temperature.
func (b *ConfigBuilder) WithTemperature(temperature float64) *ConfigBuilder {
	b.config.Temperature = temperature
	return b
}

// WithCAPIKey sets the CAPI key to use.
func (b *ConfigBuilder) WithCAPIKey(CAPIKey string) *ConfigBuilder {
	b.config.CAPIKey = CAPIKey
	return b
}

// WithCache sets the cache directory for model results.
func (b *ConfigBuilder) WithCache(cachePath string) *ConfigBuilder {
	b.config.CachePath = cachePath
	return b
}

// WithRetry enables or disables retry logic.
func (b *ConfigBuilder) WithRetry(retry bool) *ConfigBuilder {
	b.config.retry = retry
	return b
}

// Build validates the configured values and returns the final Config.
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
