package autovalidate

import (
	"fmt"
	"os"
)

type Config struct {
	Model         string
	VotingRounds  int
	RequiredVotes int
	Temperature   float64
	CAPIKey       string
	CachePath     string
	retry         bool
}

type ConfigBuilder struct {
	config *Config
}

func NewConfigBuilder() *ConfigBuilder {
	return &ConfigBuilder{
		config: &Config{
			Model:         "capi-dev-4o",
			VotingRounds:  3,
			RequiredVotes: 3,
			Temperature:   0.7,
			CAPIKey:       "",
			CachePath:     "",
			retry:         false,
		},
	}
}

func (b *ConfigBuilder) WithModel(model string) *ConfigBuilder {
	b.config.Model = model
	return b
}
func (b *ConfigBuilder) WithVotingRounds(votingRounds int) *ConfigBuilder {
	b.config.VotingRounds = votingRounds
	return b
}
func (b *ConfigBuilder) WithRequiredVotes(requiredVotes int) *ConfigBuilder {
	b.config.RequiredVotes = requiredVotes
	return b
}
func (b *ConfigBuilder) WithTemperature(temperature float64) *ConfigBuilder {
	b.config.Temperature = temperature
	return b
}
func (b *ConfigBuilder) WithCAPIKey(CAPIKey string) *ConfigBuilder {
	b.config.CAPIKey = CAPIKey
	return b
}

func (b *ConfigBuilder) WithCache(cachePath string) *ConfigBuilder {
	b.config.CachePath = cachePath
	return b
}

func (b *ConfigBuilder) WithRetry(retry bool) *ConfigBuilder {
	b.config.retry = retry
	return b
}

func (b *ConfigBuilder) Build() (*Config, error) {
	if b.config.Model == "" {
		return nil, fmt.Errorf("model cannot be empty")
	}
	if b.config.VotingRounds <= 0 {
		return nil, fmt.Errorf("voting rounds must be greater than 0")
	}
	if b.config.RequiredVotes <= 0 {
		return nil, fmt.Errorf("required votes must be greater than 0")
	}

	if b.config.RequiredVotes > b.config.VotingRounds {
		return nil, fmt.Errorf("required votes cannot be greater than voting rounds")
	}

	if b.config.Temperature < 0 || b.config.Temperature > 1 {
		return nil, fmt.Errorf("temperature must be between 0 and 1")
	}

	if b.config.CachePath != "" {
		info, err := os.Stat(b.config.CachePath)
		if err != nil {
			if os.IsNotExist(err) {
				return nil, fmt.Errorf("cache path does not exist: %s", b.config.CachePath)
			}
			return nil, fmt.Errorf("error checking cache path: %s", err)
		}
		if !info.IsDir() {
			return nil, fmt.Errorf("cache path is not a directory: %s", b.config.CachePath)
		}
	}

	return b.config, nil
}
