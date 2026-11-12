package envrouting

import (
	"context"
	"testing"

	"github.com/github/sweagentd/internal/config"
	"github.com/github/sweagentd/internal/sweagentd"
	"github.com/stretchr/testify/require"
)

type mockFF struct {
	flags map[string]bool
}

func (m *mockFF) IsEnabledForUserOrRepoOrOwner(_ context.Context, name string, _ sweagentd.RepositoryWithActor) bool {
	return m.flags[name]
}

func TestShouldProcess(t *testing.T) {
	tests := []struct {
		name            string
		environment     config.Environment
		environmentName string
		flags           map[string]bool
		expected        bool
	}{
		{
			name:            "production with no routing flags processes",
			environment:     config.EnvironmentProduction,
			environmentName: "production",
			flags:           map[string]bool{},
			expected:        true,
		},
		{
			name:            "staging with no routing flags skips",
			environment:     config.EnvironmentStaging,
			environmentName: "staging",
			flags:           map[string]bool{},
			expected:        false,
		},
		{
			name:            "production skips when routing to staging",
			environment:     config.EnvironmentProduction,
			environmentName: "production",
			flags: map[string]bool{
				"sweagentd_route_user_or_repo_to_staging": true,
			},
			expected: false,
		},
		{
			name:            "matching staging env processes",
			environment:     config.EnvironmentStaging,
			environmentName: "staging",
			flags: map[string]bool{
				"sweagentd_route_user_or_repo_to_staging": true,
			},
			expected: true,
		},
		{
			name:            "non-matching staging env skips",
			environment:     config.EnvironmentStaging,
			environmentName: "staging-jedi-knight",
			flags: map[string]bool{
				"sweagentd_route_user_or_repo_to_staging": true,
			},
			expected: false,
		},
		{
			name:            "jedi-knight processes with matching flag",
			environment:     config.EnvironmentStaging,
			environmentName: "staging-jedi-knight",
			flags: map[string]bool{
				"sweagentd_route_user_or_repo_to_staging_jedi_knight": true,
			},
			expected: true,
		},
		{
			name:            "sith-lord processes with matching flag",
			environment:     config.EnvironmentStaging,
			environmentName: "staging-sith-lord",
			flags: map[string]bool{
				"sweagentd_route_user_or_repo_to_staging_sith_lord": true,
			},
			expected: true,
		},
		{
			name:            "staging wins over jedi-knight when both flagged",
			environment:     config.EnvironmentStaging,
			environmentName: "staging",
			flags: map[string]bool{
				"sweagentd_route_user_or_repo_to_staging":             true,
				"sweagentd_route_user_or_repo_to_staging_jedi_knight": true,
			},
			expected: true,
		},
		{
			name:            "jedi-knight loses to staging when both flagged",
			environment:     config.EnvironmentStaging,
			environmentName: "staging-jedi-knight",
			flags: map[string]bool{
				"sweagentd_route_user_or_repo_to_staging":             true,
				"sweagentd_route_user_or_repo_to_staging_jedi_knight": true,
			},
			expected: false,
		},
		{
			name:            "jedi-knight wins over sith-lord when both flagged",
			environment:     config.EnvironmentStaging,
			environmentName: "staging-jedi-knight",
			flags: map[string]bool{
				"sweagentd_route_user_or_repo_to_staging_jedi_knight": true,
				"sweagentd_route_user_or_repo_to_staging_sith_lord":   true,
			},
			expected: true,
		},
		{
			name:            "sith-lord loses to jedi-knight when both flagged",
			environment:     config.EnvironmentStaging,
			environmentName: "staging-sith-lord",
			flags: map[string]bool{
				"sweagentd_route_user_or_repo_to_staging_jedi_knight": true,
				"sweagentd_route_user_or_repo_to_staging_sith_lord":   true,
			},
			expected: false,
		},
		{
			name:            "baby-yoda processes with matching flag",
			environment:     config.EnvironmentStaging,
			environmentName: "staging-baby-yoda",
			flags: map[string]bool{
				"sweagentd_route_user_or_repo_to_staging_baby_yoda": true,
			},
			expected: true,
		},
		{
			name:            "baby-yoda loses to staging when both flagged",
			environment:     config.EnvironmentStaging,
			environmentName: "staging-baby-yoda",
			flags: map[string]bool{
				"sweagentd_route_user_or_repo_to_staging":           true,
				"sweagentd_route_user_or_repo_to_staging_baby_yoda": true,
			},
			expected: false,
		},
		{
			name:            "baby-yoda loses to jedi-knight when both flagged",
			environment:     config.EnvironmentStaging,
			environmentName: "staging-baby-yoda",
			flags: map[string]bool{
				"sweagentd_route_user_or_repo_to_staging_jedi_knight": true,
				"sweagentd_route_user_or_repo_to_staging_baby_yoda":   true,
			},
			expected: false,
		},
		{
			name:            "baby-yoda loses to sith-lord when both flagged",
			environment:     config.EnvironmentStaging,
			environmentName: "staging-baby-yoda",
			flags: map[string]bool{
				"sweagentd_route_user_or_repo_to_staging_sith_lord": true,
				"sweagentd_route_user_or_repo_to_staging_baby_yoda": true,
			},
			expected: false,
		},
		{
			name:            "staging wins when all four routing flags are set",
			environment:     config.EnvironmentStaging,
			environmentName: "staging",
			flags: map[string]bool{
				"sweagentd_route_user_or_repo_to_staging":             true,
				"sweagentd_route_user_or_repo_to_staging_jedi_knight": true,
				"sweagentd_route_user_or_repo_to_staging_sith_lord":   true,
				"sweagentd_route_user_or_repo_to_staging_baby_yoda":   true,
			},
			expected: true,
		},
		{
			name:            "baby-yoda does not process when all four flags set",
			environment:     config.EnvironmentStaging,
			environmentName: "staging-baby-yoda",
			flags: map[string]bool{
				"sweagentd_route_user_or_repo_to_staging":             true,
				"sweagentd_route_user_or_repo_to_staging_jedi_knight": true,
				"sweagentd_route_user_or_repo_to_staging_sith_lord":   true,
				"sweagentd_route_user_or_repo_to_staging_baby_yoda":   true,
			},
			expected: false,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			router := NewRouter(&mockFF{flags: tc.flags}, tc.environment, tc.environmentName)
			result := router.ShouldProcess(context.Background(), 1, 2, 3)
			require.Equal(t, tc.expected, result)
		})
	}
}
