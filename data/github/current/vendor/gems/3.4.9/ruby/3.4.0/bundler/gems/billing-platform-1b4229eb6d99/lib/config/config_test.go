package config

import (
	"testing"

	goconfig "github.com/github/go-config"
	"github.com/stretchr/testify/assert"
)

func TestEnvironmentPredicates(t *testing.T) {
	t.Run("IsRemoteNonProd", func(t *testing.T) {
		t.Run("returns true when environment is development", func(t *testing.T) {
			cfg := Config{Environment: "development"}
			got := cfg.IsRemoteNonProd()
			if !got {
				t.Errorf("expected true, got %v", got)
			}
		})
	})

	t.Run("IsLocal", func(t *testing.T) {
		t.Run("returns true when environment is local", func(t *testing.T) {
			cfg := Config{Environment: "local"}
			got := cfg.IsLocal()
			if !got {
				t.Errorf("expected true, got %v", got)
			}
		})
	})

	t.Run("IsProduction", func(t *testing.T) {
		t.Run("returns true when environment is production", func(t *testing.T) {
			cfg := Config{Environment: "production"}
			got := cfg.IsProduction()
			if !got {
				t.Errorf("expected true, got %v", got)
			}
		})

		t.Run("returns true when environment is staff-wus2-01", func(t *testing.T) {
			cfg := Config{Environment: "staff-wus2-01"}
			got := cfg.IsProduction()
			if !got {
				t.Errorf("expected true, got %v", got)
			}
		})

		t.Run("returns true when environment is prod-weu-01", func(t *testing.T) {
			cfg := Config{Environment: "prod-weu-01"}
			got := cfg.IsProduction()
			if !got {
				t.Errorf("expected true, got %v", got)
			}
		})

		t.Run("returns true when environment is prod-sdc-01", func(t *testing.T) {
			cfg := Config{Environment: "prod-sdc-01"}
			got := cfg.IsProduction()
			if !got {
				t.Errorf("expected true, got %v", got)
			}
		})

		t.Run("returns false when environment is not production", func(t *testing.T) {
			cfg := Config{Environment: "test"}
			got := cfg.IsProduction()
			if got {
				t.Errorf("expected false, got %v", got)
			}
		})
	})
}

func Test_LoadProximaConfig(t *testing.T) {
	testCases := []struct {
		environment              string
		expectedMonolithTwirpURL string
		expectedAqueductAddress  string
	}{
		{"staff-wus2-01", "https://internal-api.service.staff-wus2-01.github.net/internal", "https://aqueduct.service.staff-wus2-01.github.net"},
		{"prod-weu-01", "https://internal-api.service.prod-weu-01.github.net/internal", "https://aqueduct.service.prod-weu-01.github.net"},
		{"prod-sdc-01", "https://internal-api.service.prod-sdc-01.github.net/internal", "https://aqueduct.service.prod-sdc-01.github.net"},
		{"development", "http://api.github.localhost/internal", "http://localhost:18081"},
		{"production", "https://internal-api.service.iad.github.net/internal", "https://aqueduct-gateway-production.service.iad.github.net"},
		{"production/canary", "https://internal-api.service.iad.github.net/internal", "https://aqueduct-gateway-production.service.iad.github.net"},
	}

	for _, tc := range testCases {
		t.Run(tc.environment, func(t *testing.T) {
			// create config and load the default values before running LoadProximaConfig
			cfg := &Config{}
			if err := goconfig.Load(cfg); err != nil {
				t.Errorf("unexpected error: %v", err)
			}
			cfg.Environment = tc.environment

			cfg.LoadMonolithConfig()

			assert.Equal(t, tc.expectedMonolithTwirpURL, cfg.MonolithTwirpURL)
			assert.Equal(t, tc.expectedAqueductAddress, cfg.AqueductAddress)
		})
	}
}

func Test_setAzureLocationForEnvironment(t *testing.T) {
	testCases := []struct {
		environment string
		expected    string
	}{
		{"staff-wus2-01", "westus2"},
		{"prod-weu-01", "westeurope"},
		{"prod-sdc-01", "swedencentral"},
		{"prod-ae-01", "australiaeast"},
		{"unknown-env", "eastus"},
		{"development", "eastus"},
		{"production", "eastus"},
		{"production/canary", "eastus"},
		{"local", "eastus"},
	}

	for _, tc := range testCases {
		t.Run(tc.environment, func(t *testing.T) {
			cfg := &Config{Environment: tc.environment}
			cfg.setAzureLocationForEnvironment()
			if cfg.AzureCommerceLocation != tc.expected {
				t.Errorf("For environment %s, expected %s but got %s", tc.environment, tc.expected, cfg.AzureCommerceLocation)
			}
		})
	}
}
