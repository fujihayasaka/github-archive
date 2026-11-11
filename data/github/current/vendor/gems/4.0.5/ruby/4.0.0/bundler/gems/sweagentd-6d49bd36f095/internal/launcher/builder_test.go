package launcher

import (
	"testing"

	"github.com/stretchr/testify/require"

	"github.com/github/sweagentd/internal/config"
	"github.com/github/sweagentd/internal/observability"
)

// TestNewBuilderFromConfig_IsStagingEnvironment verifies that the builder
// flags every staging-prefixed environment (e.g. "staging", "staging-sith-lord")
// as a staging environment, not just the literal "staging".
func TestNewBuilderFromConfig_IsStagingEnvironment(t *testing.T) {
	tests := []struct {
		envName           string
		wantIsStaging     bool
		wantIsDevelopment bool
		wantIsProxima     bool
	}{
		{envName: "staging", wantIsStaging: true},
		{envName: "staging-sith-lord", wantIsStaging: true},
		{envName: "staging-jedi-master", wantIsStaging: true},
		{envName: "development", wantIsDevelopment: true},
		{envName: "production"},
		{envName: "staff-foo", wantIsProxima: true},
		{envName: "prod-foo", wantIsProxima: true},
	}

	for _, tt := range tests {
		t.Run(tt.envName, func(t *testing.T) {
			env, err := config.ParseEnvironment(tt.envName)
			require.NoError(t, err)

			cfg := &config.Config{
				EnvironmentName: tt.envName,
				Environment:     env,
				Sha:             "test-sha",
			}

			b, err := NewBuilderFromConfig(cfg, observability.NewNoopExporters(), nil, nil, nil, nil, nil)
			require.NoError(t, err)

			require.Equal(t, tt.wantIsStaging, b.actionsOpts.IsStagingEnvironment, "actions IsStagingEnvironment")
			require.Equal(t, tt.wantIsStaging, b.dockerOpts.IsStagingEnvironment, "docker IsStagingEnvironment")
			require.Equal(t, tt.wantIsDevelopment, b.actionsOpts.IsDevelopmentEnvironment, "actions IsDevelopmentEnvironment")
			require.Equal(t, tt.wantIsProxima, b.actionsOpts.IsProximaEnvironment, "actions IsProximaEnvironment")
		})
	}
}
