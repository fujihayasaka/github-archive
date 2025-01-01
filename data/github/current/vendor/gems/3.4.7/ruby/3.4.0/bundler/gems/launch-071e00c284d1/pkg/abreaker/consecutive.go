package abreaker

import (
	"context"
	"errors"

	circuit "github.com/rubyist/circuitbreaker"

	"github.com/github/launch/observability"
)

func newConsecutiveBreaker(ctx context.Context, obs *observability.Observability, cfg *ConsecutiveBreakerConfig) (*circuit.Breaker, error) {
	err := cfg.validate()
	if err != nil {
		return nil, err
	}

	breaker := circuit.NewConsecutiveBreaker(cfg.Threshold)
	observability.MonitorCircuitBreaker(ctx, obs, cfg.Name, breaker)
	return breaker, nil
}

type ConsecutiveBreakerConfig struct {
	Threshold int64
	// WindowSize is the duration of the evaluation window in seconds
	WindowSize int
	// Name is the name of the breaker, it's used as a metric name for the breaker
	Name string
}

func (cfg *ConsecutiveBreakerConfig) validate() error {
	if cfg.Threshold == 0 {
		return errors.New("invalid breaker configuration, threshold must be configured")
	}
	return nil
}

type ConsecutiveBreakerBuilder = func(cfg Config) *ConsecutiveBreakerConfig

func buildConsecutiveBreakerConfig(threshold int64, name string) *ConsecutiveBreakerConfig {
	return &ConsecutiveBreakerConfig{
		Threshold: threshold,
		Name:      name,
	}
}

func BuildLaunchDBClientConfig(cfg Config) *ConsecutiveBreakerConfig {
	return buildConsecutiveBreakerConfig(
		cfg.LaunchDBClientBreakerThreshold,
		cfg.LaunchDBClientBreakerName,
	)
}

func BuildLaunchRODBClientConfig(cfg Config) *ConsecutiveBreakerConfig {
	return buildConsecutiveBreakerConfig(
		cfg.LaunchRODBClientBreakerThreshold,
		cfg.LaunchRODBClientBreakerName,
	)
}

func BuildPayloadsClientConfig(cfg Config) *ConsecutiveBreakerConfig {
	return buildConsecutiveBreakerConfig(
		cfg.PayloadsClientBreakerThreshold,
		cfg.PayloadsClientBreakerName,
	)
}

func BuildJobCLITokenServiceConfig(cfg Config) *ConsecutiveBreakerConfig {
	return buildConsecutiveBreakerConfig(
		cfg.JobCLITokenServiceClientBreakerThreshold,
		cfg.JobCLITokenServiceBreakerName,
	)
}

func BuildAzpS2SConfig(cfg Config) *ConsecutiveBreakerConfig {
	return buildConsecutiveBreakerConfig(
		cfg.AzpS2SBreakerThreshold,
		cfg.AzpS2SBreakerName,
	)
}

func BuildAuthzdClientConfig(cfg Config) *ConsecutiveBreakerConfig {
	return buildConsecutiveBreakerConfig(
		cfg.AuthzdClientBreakerThreshold,
		cfg.AuthzdClientBreakerName,
	)
}
