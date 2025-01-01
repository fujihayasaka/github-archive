package launchconfig

import (
	"strconv"
	"testing"

	"github.com/stretchr/testify/require"
)

func TestEnvironmentTag(t *testing.T) {
	tests := []struct {
		name          string
		launchEnv     AppEnv
		isMultiTenant bool
		expectedTag   string
	}{
		{
			name:          "Production environment",
			launchEnv:     ProductionAppEnv,
			isMultiTenant: false,
			expectedTag:   "production",
		},
		{
			name:          "Multitenant environment",
			launchEnv:     ProductionAppEnv,
			isMultiTenant: true,
			expectedTag:   "production",
		},
		{
			name:          "Lab environment",
			launchEnv:     LabAppEnv,
			isMultiTenant: false,
			expectedTag:   "lab",
		},
		{
			name:          "Test environment",
			launchEnv:     TestAppEnv,
			isMultiTenant: false,
			expectedTag:   "test",
		},
		{
			name:          "Development environment",
			launchEnv:     DevelopmentAppEnv,
			isMultiTenant: false,
			expectedTag:   "development",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ResetConfig()

			t.Setenv("LAUNCH_ENV", tt.launchEnv.String())
			t.Setenv("LAUNCH_IS_MULTI_TENANT", strconv.FormatBool(tt.isMultiTenant))

			require.Equal(t, tt.expectedTag, EnvironmentTag())
		})
	}
}
